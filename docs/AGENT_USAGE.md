# Generate narration from Codex or Claude

Any agent with shell access on the same Mac can use Voice Studio to create MP3 narration. The workflow uses the local HTTP API; it does not require an OpenAI or Anthropic API, an MCP server, or browser automation. An agent running on another machine cannot reach this loopback server.

## Use the narration helper

Install Voice Studio with the command in [README.md](../README.md). The helper additionally requires Python 3. It starts the Swift-source server without opening a browser, checks readiness, renders audio, saves the MP3, and stops only the server it started.

```sh
printf '%s' 'This narration was generated locally with Nora.' | \
  python3 ~/.local/share/voice-studio/scripts/narrate.py \
  --output narration.mp3
```

For a UTF-8 script file and a different speaking rate:

```sh
python3 ~/.local/share/voice-studio/scripts/narrate.py \
  --text-file script.txt \
  --output voiceover.mp3 \
  --voice com.apple.siri.natural.Nora \
  --rate 0.48
```

Inside a cloned repository, use `python3 scripts/narrate.py` instead. Relative input and output paths resolve against the caller's working directory. The helper prints the absolute output path on success and refuses to overwrite an existing file. Choose another filename for a new version.

There is no voice substitution. If Nora is absent or cannot export audio, the helper reports the error. Pick another exact installed natural Siri voice ID explicitly. Speech rate must be from `0.20` through `0.65`; it is not a playback multiplier.

## Example prompt for your agent

> Generate a voiceover from script.txt using the installed Voice Studio helper at ~/.local/share/voice-studio/scripts/narrate.py. Use Nora at rate 0.48 and save the result as voiceover.mp3. Check the resulting MP3 codec and duration with ffprobe. If prerequisites or Nora are unavailable, report the blocker instead of switching voice providers. Do not expose the private session token.

The same prompt works as a task instruction for a local Codex or Claude session that can execute commands. There is no special agent integration or plugin installation.

## Reuse an existing session

The helper can reuse a running browser session. Set the full URL privately in the environment, using the actual port and token from Terminal:

```sh
export VOICE_STUDIO_URL='http://127.0.0.1:PORT/#SESSION_TOKEN'
printf '%s' 'A second narration from the existing session.' | \
  python3 scripts/narrate.py --output second-narration.mp3
unset VOICE_STUDIO_URL
```

When reusing a session, the helper leaves the server running. Another browser render or agent request can occupy the single generation slot; wait before retrying a 409 response. Keep tokens out of shared logs, screenshots, source control, and prompts sent to other services.

## Call the API directly

1. Start `~/.local/bin/voice-studio --no-open` as a persistent process.
2. Read the `Open:` line and separate the base URL from the fragment token.
3. GET `/api/status` with `Authorization: Bearer TOKEN`. Check `specs.ready` and choose an exact identifier from `voices`.
4. POST `/api/generate` with JSON containing `text`, `voice`, and `rate`, plus the same Authorization header and `Content-Type: application/json`.
5. Wait for the response and download its `download` path using the same Authorization header.
6. Save the MP3 before stopping a server you own. Do not stop an existing user session.

Generation can take up to five minutes for speech and two minutes for encoding, so allow a request timeout above seven minutes. Submit one passage at a time. The server accepts at most 10,000 Swift characters and a 64 KiB JSON body. Split long scripts at sentence boundaries and save each segment separately.

Complete curl examples and HTTP status meanings are in [the usage guide](USAGE.md#using-the-local-http-api).

## Verify and use the audio

```sh
ffprobe -v error -show_entries format=duration:stream=codec_name \
  -of json voiceover.mp3
```

The audio stream should report `mp3` and a nonzero duration. Use the saved MP3 in a video editor, presentation, or ffmpeg workflow. Downloads saved by the helper remain after the server shuts down.

## Persistent agent instruction

Add this instruction to your agent's own instruction file if you want this workflow used routinely:

> For narration and voiceovers, use the local Voice Studio helper to generate MP3 audio. Prefer Nora when installed, preserve the requested script, and verify codec and duration. Report blockers rather than silently using another provider.

Place it in the instruction file your agent actually reads; this repository does not modify Codex or Claude settings automatically.
