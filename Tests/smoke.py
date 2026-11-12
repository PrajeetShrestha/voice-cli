#!/usr/bin/env python3
"""Integration tests against the compiled macOS CLI; no third-party Python packages."""
import json, pathlib, re, signal, subprocess, tempfile, urllib.request, urllib.error, concurrent.futures, os
ROOT = pathlib.Path(__file__).resolve().parents[1]
command = ['/usr/bin/swift', str(ROOT/'Sources/VoiceStudio/main.swift'), '--no-open'] if not os.environ.get('TEST_COMPILED') else [str(ROOT/'.build/release/voice-studio'), '--no-open']
p = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=None, text=True)

def check(condition, label):
    assert condition, label
    print('PASS:', label, flush=True)
try:
    for line in p.stdout:
        if line.startswith('Open: '):
            url, token = line.strip()[6:].split('/#'); break
    else: raise AssertionError('Server did not start')
    def req(path, payload=None, auth=True, origin=None, raw=False):
        headers = {'Authorization': 'Bearer '+token} if auth else {}
        if origin: headers['Origin'] = origin
        data = None
        if payload is not None:
            headers['Content-Type'] = 'application/json'
            data = json.dumps(payload).encode()
        request = urllib.request.Request(url+path, data=data, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=330) as r: return r.status, r.read()
        except urllib.error.HTTPError as e: return e.code, e.read()
    code, html = req('/', auth=False); check(code == 200 and b'Device readiness' in html, 'HTML served')
    check(req('/api/status', auth=False)[0] == 403, 'Unauthenticated API blocked')
    check(req('/api/status', origin='https://example.com')[0] == 403, 'Foreign origin blocked')
    code, body = req('/api/status'); d=json.loads(body)
    check(code == 200 and d['specs']['ready'] and d['voices'], 'Readiness and installed voices')
    print('DEVICE:', json.dumps(d['specs']), flush=True)
    check(all(v['id'].startswith('com.apple.siri.natural.') for v in d['voices']), 'Only natural Siri voices listed')
    voice=next((v for v in d['voices'] if v['id']=='com.apple.siri.natural.Nora'),d['voices'][0])
    if os.environ.get('TEST_VOICE_ID'):
        voice=next(v for v in d['voices'] if v['id']==os.environ['TEST_VOICE_ID'])
    print('Selected voice:',voice,flush=True)
    payload={'text':'Hello. Unicode works: café, naïve, and a little sunshine. This is a local MP3 test.', 'voice':voice['id'], 'rate':0.48}
    check(req('/api/generate',{**payload,'text':'  '})[0] == 400, 'Empty input rejected')
    check(req('/api/generate',{**payload,'voice':'not-installed'})[0] == 400, 'Unknown voice rejected')
    check(req('/api/generate',{**payload,'rate':1.0})[0] == 400, 'Rate bounds enforced')
    check(req('/api/generate',{**payload,'text':'a'*10001})[0] == 400, 'Text length enforced')
    check(req('/api/audio/../../etc/passwd')[0] == 404, 'Traversal blocked')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda _:req('/api/generate',payload),range(2)))
    print('Generation responses:', results, flush=True)
    check(sorted(r[0] for r in results)==[200,409], 'Concurrent rendering rejected safely')
    result=json.loads(next(body for code,body in results if code==200))
    code,audio=req(result['download']); check(code==200 and len(audio)>1000,'Generated MP3 downloads')
    with tempfile.NamedTemporaryFile(suffix='.mp3') as f:
        f.write(audio); f.flush()
        probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name','-of','json',f.name]))
        check(probe['streams'][0]['codec_name']=='mp3' and float(probe['format']['duration'])>1,'ffprobe verifies MP3 codec and duration')
        print('MP3 duration:',probe['format']['duration'], flush=True)
    code,body=req('/api/generate',{**payload,'text':'A second narration works, too.'});check(code==200,'Repeated generation succeeds')
    check(not json.loads(req('/api/status')[1])['busy'],'Busy flag reset')
finally:
    p.send_signal(signal.SIGINT)
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait()
