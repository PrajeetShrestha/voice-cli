#!/usr/bin/env python3
"""Build the illustrated demo using its frames, Voice Studio narration, and ffmpeg."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)

def timestamp(value):
    milliseconds = round(value * 1000)
    seconds, ms = divmod(milliseconds, 1000)
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return f'{hours:02}:{minutes:02}:{seconds:02},{ms:03}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/demo/voice-studio-demo.mp4')
    args = parser.parse_args()
    scenes = json.loads((ROOT / 'demo/scenes.json').read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subtitles = []
    offset = 0
    with tempfile.TemporaryDirectory(prefix='voice-studio-demo-') as work:
        work = Path(work)
        clips = []
        for index, scene in enumerate(scenes, 1):
            print(f'Building chapter {index}/{len(scenes)}: {scene["title"]}', flush=True)
            script = work / f'{index}.txt'
            script.write_text(scene['narration'])
            audio = work / f'{index}.mp3'
            run(sys.executable, ROOT / 'scripts/narrate.py', '--text-file', script, '--output', audio, '--rate', '0.48')
            duration = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', str(audio)])) + 0.7
            # Split closed captions into readable groups of roughly twelve words.
            words = scene['narration'].split()
            groups = [words[start:start+12] for start in range(0, len(words), 12)]
            for group_index, group in enumerate(groups):
                start = offset + (duration-0.7) * group_index / len(groups)
                end = offset + (duration-0.7) * (group_index+1) / len(groups)
                subtitles.append(f'{len(subtitles)+1}\n{timestamp(start)} --> {timestamp(end)}\n{" ".join(group)}\n')
            clip = work / f'{index}.mp4'
            run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-loop', '1', '-framerate', '24', '-i', ROOT / f'demo/frames/{index:02}.png', '-i', audio,
                '-vf', 'scale=1600:900,setsar=1,fade=t=in:st=0:d=0.25', '-af', 'apad', '-t', str(duration), '-c:v', 'libx264', '-preset', 'fast', '-tune', 'stillimage', '-crf', '24', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', clip)
            clips.append(clip)
            offset += duration
        listing = work / 'clips.txt'
        listing.write_text(''.join(f"file '{clip}'\n" for clip in clips))
        subtitle_file = args.output.with_suffix('.srt')
        subtitle_file.write_text('\n'.join(subtitles))
        combined = work / 'combined.mp4'
        run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', listing, '-c', 'copy', combined)
        run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', combined, '-i', subtitle_file, '-map', '0:v', '-map', '0:a', '-map', '1:0', '-c', 'copy', '-c:s', 'mov_text', '-metadata:s:s:0', 'language=eng', '-metadata', 'title=Voice Studio walkthrough', '-movflags', '+faststart', args.output)
    print(f'Created {args.output} ({offset:.1f} seconds)')


if __name__ == '__main__':
    main()
