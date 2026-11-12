#!/usr/bin/env python3
"""Generate local MP3 narration for scripts and coding agents using Voice Studio."""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request


def request(base, token, path, payload=None):
    headers = {'Authorization': 'Bearer ' + token}
    data = None
    if payload is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(base + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=440) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        try:
            detail = json.loads(error.read()).get('error', str(error))
        except (ValueError, AttributeError):
            detail = str(error)
        raise RuntimeError(detail) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--text-file', type=Path, help='UTF-8 input file; otherwise read stdin')
    parser.add_argument('--output', type=Path, required=True, help='Destination MP3; must not already exist')
    parser.add_argument('--voice', default='com.apple.siri.natural.Nora', help='Exact installed natural Siri voice ID')
    parser.add_argument('--rate', type=float, default=0.48, help='Apple speech rate from 0.20 through 0.65')
    parser.add_argument('--url', default=os.environ.get('VOICE_STUDIO_URL'), help='Existing private session URL; also read from VOICE_STUDIO_URL')
    args = parser.parse_args()
    if not 0.2 <= args.rate <= 0.65:
        parser.error('--rate must be between 0.20 and 0.65')
    if args.output.exists():
        parser.error('output already exists; choose another filename')
    text = args.text_file.read_text(encoding='utf-8') if args.text_file else sys.stdin.read()
    if not text.strip():
        parser.error('provide nonempty text through --text-file or stdin')
    payload = {'text': text, 'voice': args.voice, 'rate': args.rate}
    if len(json.dumps(payload).encode('utf-8')) > 65536:
        parser.error('JSON body exceeds 64 KiB; split the text into smaller passages')
    process = None
    temporary = None
    try:
        session_url = args.url
        if not session_url:
            launcher = Path(__file__).resolve().parents[1] / 'run.sh'
            process = subprocess.Popen([str(launcher), '--no-open'], stdout=subprocess.PIPE, text=True)
            lines = queue.Queue()
            def read_stdout():
                for line in process.stdout:
                    lines.put(line)
                lines.put(None)
            threading.Thread(target=read_stdout, daemon=True).start()
            while True:
                try:
                    line = lines.get(timeout=90)
                except queue.Empty:
                    raise RuntimeError('Server startup timed out')
                if line is None:
                    raise RuntimeError('Server stopped before printing its session URL')
                if line.startswith('Open: '):
                    session_url = line[6:].strip()
                    break
        parsed = urllib.parse.urlsplit(session_url)
        if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.port or not parsed.fragment or parsed.username or parsed.password or parsed.query or parsed.path != '/':
            raise RuntimeError('Use the complete http://127.0.0.1:PORT/#TOKEN URL printed by Voice Studio')
        base, token = 'http://' + parsed.netloc, parsed.fragment
        status = json.loads(request(base, token, '/api/status'))
        if not status['specs']['ready']:
            raise RuntimeError('; '.join(status['specs']['blockers']))
        if args.voice not in {voice['id'] for voice in status['voices']}:
            raise RuntimeError('Requested voice is not installed. Read /api/status and choose an exact available ID; no voice was substituted.')
        result = json.loads(request(base, token, '/api/generate', payload))
        audio = request(base, token, result['download'])
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=args.output.parent, prefix='.voice-studio-', suffix='.mp3', delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(audio)
        # A hard link atomically refuses to overwrite an existing destination.
        os.link(temporary, args.output)
        temporary.unlink()
        temporary = None
        print(str(args.output.resolve()))
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        if process is not None:
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            if process.stdout:
                process.stdout.close()


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print('Voice Studio: ' + str(error), file=sys.stderr)
        sys.exit(1)
