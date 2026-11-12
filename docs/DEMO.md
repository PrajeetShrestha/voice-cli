# Voice Studio narrated walkthrough

[Watch on YouTube](https://www.youtube.com/watch?v=ZE_4kn-xiFc) or [download the MP4](https://github.com/PrajeetShrestha/voice-cli/releases/download/v0.1.0/voice-studio-demo.mp4). The walkthrough uses illustrated command examples, real Web UI screenshots, and Nora narration generated locally through Voice Studio. It covers manual use and agent automation on the same Mac.

## Rebuild the video

Requires the same Voice Studio prerequisites, plus Python 3 and ffmpeg with libx264 and AAC encoding. From a source checkout:

```sh
python3 demo/build.py
```

The script uses the included chapter images in `demo/frames`, reads the narration from `demo/scenes.json`, and runs `scripts/narrate.py` for every chapter. It creates `docs/demo/voice-studio-demo.mp4` and `docs/demo/voice-studio-demo.srt`. Narration uses Nora at rate 0.48. No external speech service is used.

By default, the narration helper starts and stops a private CLI process for each chapter. Set `VOICE_STUDIO_URL` to an existing private session URL to reuse that server instead. Do not run other renders in that session while building.

The MP4 contains an H.264 video stream, AAC audio, and selectable English captions. Caption timing is estimated from each chapter's narration duration; it is not word-level speech alignment. The MP4 is distributed as a GitHub release asset rather than committed to Git.

## Transcript

### 1 Local narration for people and agents

Meet Voice Studio. A small Mac command line tool with a browser interface. It turns text into downloadable MP3 narration using installed Siri voices. This video's narration was made with Voice Studio itself, using Nora.

### 2 Install once and open the Web UI

Start with the one line installer at the top of the GitHub readme. You need macOS, Apple command line tools, and a downloaded natural Siri voice. The installer uses your existing encoder, or installs ffmpeg through an existing Homebrew setup. Then run the installed voice studio command. Leave Terminal open while you work.

### 3 Create your first recording

In Create audio, paste your script. Choose the language and region, then an installed Siri voice. Nora is selected when available. Click Generate MP3. The audio plays when it is ready, and Download MP3 saves a copy. If your browser blocks autoplay, press Play.

### 4 Change the voice or speech speed

Move the speech speed slider left for slower speech, or right for faster speech. It changes the generated recording, not the player's playback speed. After the first successful render, changing language, voice, or speed regenerates and plays updated audio. Rapid changes are combined. Editing text alone still needs Generate MP3.

### 5 Give Codex or Claude a narration tool

Agents with shell access on the same Mac can use the included Python helper. Ask Codex or Claude to read a script file, use Nora, and save a voiceover MP3. The helper starts Voice Studio without a browser, checks readiness, generates the recording, and shuts down its own server. Python three is required for this helper.

### 6 Use the local API directly

For a custom agent workflow, start Voice Studio with no open. Read the private session URL from Terminal. Send the token as a bearer authorization header. Check status, post text, a voice identifier, and rate to generate, then download the returned audio path. Run requests one at a time and keep the token private.

### 7 Verify the MP3 and save your work

Use ffprobe to verify that the saved file is MP3 with a nonzero duration. Your agent can then use it in a demo, presentation, or video. The server is local to this Mac. Download recordings before stopping the CLI, because Control C deletes temporary session audio. Saved files remain yours.

### 8 Start with the GitHub guide

The GitHub project includes the installer, screenshots, a detailed usage guide, and copyable agent instructions. Start with a short script, choose Nora, and generate your first recording. The same local tool works for you and your coding agents.
