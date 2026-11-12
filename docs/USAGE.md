# Voice Studio usage guide

Voice Studio turns text into MP3 narration using the natural Siri voices installed on your Mac. Start it in Terminal, create audio in the browser, and download recordings you want to keep. Speech synthesis and encoding run locally.

## Install the CLI

```sh
curl -fsSL https://raw.githubusercontent.com/PrajeetShrestha/voice-cli/v0.1.0/install.sh | /bin/sh
~/.local/bin/voice-studio
```

The installer stores source in `~/.local/share/voice-studio` and creates the launcher in `~/.local/bin`. It requires Apple Command Line Tools or Xcode and uses an existing ffmpeg or installs it with an existing Homebrew setup. Download Siri voices separately through macOS. If using the installed app, substitute `~/.local/bin/voice-studio` for `./run.sh` throughout this guide.

## Quick start

1. Open Terminal and start the app:

   ```sh
   cd ~/Projects/voice-cli
   ./run.sh
   ```

2. Leave Terminal running. Your default browser opens Voice Studio automatically.
3. Open **Device readiness** if generation is unavailable. Resolve any listed blockers, then restart the CLI.
4. In **Create audio**, enter text and choose a language, Siri voice, and speech speed. Nora is selected when installed.
5. Click **Generate MP3**. When generation finishes, the audio plays automatically. If your browser blocks autoplay, press Play.
6. Click **Download MP3** to save a permanent copy.
7. After this first successful generation, changing language, voice, or speed automatically generates and plays updated audio.
8. When finished, return to Terminal and press **Control-C**. Session audio is deleted; saved downloads remain.

## Requirements

| Requirement | What to check |
| --- | --- |
| macOS 13 or newer | Supports Intel and Apple silicon. Linux and Windows cannot run this AVFoundation app. |
| Swift 5.9 or newer | Install Xcode or Apple Command Line Tools. Check with `swift --version`. |
| Installed natural Siri voice | Download a voice through macOS System Settings if none is available. |
| ffmpeg with libmp3lame | Used to encode speech as a real MP3. |
| At least 256 MiB free temporary disk space | This is the app's safety reserve. Longer recordings can require more space. |

There is no API key, login, cloud speech subscription, Python server, or JavaScript dependency installation. Python is optional for development tests only.

To check the local tools:

```sh
sw_vers -productVersion
xcrun --find swift
swift --version
command -v ffmpeg
ffmpeg -hide_banner -encoders
```

The encoder list must include `libmp3lame`. If you already use Homebrew and need ffmpeg, install it yourself:

```sh
brew install ffmpeg
```

The running CLI never installs tools or downloads voices automatically. The separate installer can install ffmpeg through an existing Homebrew setup. Voice downloads through macOS may require internet; installed voices synthesize locally.

## Starting and stopping

### Open the browser automatically

```sh
cd ~/Projects/voice-cli
./run.sh
```

Startup can take a few seconds while Swift compiles the source. Terminal prints a session URL shaped like this:

```text
Open: http://127.0.0.1:PORT/#SESSION_TOKEN
```

Use the actual URL printed by your current process. The port and token change every time you start the CLI. Keep the complete URL private because it authorizes access to this session.

### Start without opening a browser

```sh
./run.sh --no-open
```

Open the printed URL manually on the same Mac when ready. This mode also serves the local API for scripts.

`--no-open` is the only implemented application option. There are no dedicated text, voice, speed, output-file, port, or help flags. Use the browser controls or the HTTP API described below.

### Stop or restart

Press **Control-C** in the Terminal running Voice Studio. To restart, run `./run.sh` again and use the newly printed URL. Old tabs cannot connect to the new session using their previous URL.

Closing the browser does not stop the CLI or cancel a render. There is no render cancel button. Stopping the CLI ends the session and removes its audio, so download anything you need first.

## Creating narration

The **Create audio** tab contains the text field, language and voice menus, speech speed slider, generation button, and audio output. On desktop, text and voice controls sit beside each other; mobile uses a compact arrangement.

### Text to read

Paste or type plain text. Punctuation and sentence breaks help structure narration. Unicode is supported; SSML and other speech markup are not interpreted.

The browser accepts up to 10,000 UTF-16 code units, so some emoji occupy two positions. The visible counter counts Unicode code points, while the server separately enforces a 10,000 Swift-character limit and a 64 KiB JSON-body limit. These measures differ for some Unicode text; large passages may reach the byte limit first. Empty or whitespace-only text is rejected.

For long passages, generate smaller sections and download each one. Synthesis can take several minutes, with a five-minute synthesis timeout followed by up to two minutes for encoding.

### Language and region

Choose a readable language and region such as **English (United States)** or **Spanish (Spain)** to filter the installed voices. **All languages** shows the whole available catalog.

This control filters voice accents and languages; it does not translate your text. Select a voice appropriate for the language you wrote. Changing the language preserves the selected voice if it still matches; otherwise, the first matching voice becomes selected.

### Siri voice

Choose an installed voice such as **Nora**, **Simone**, or **Luisa**. Names and availability depend on your Mac. When an identifier does not provide a personal name, the UI keeps Apple's numbered voice name. The selected voice's language and installed quality appear below the menu.

The preferred Nora is `com.apple.siri.natural.Nora`, an American English Siri voice reported by macOS as Voice 4. It is distinct from the Norwegian system voice named Nora. The application only lists identifiers beginning with `com.apple.siri.natural.`; standard and novelty system voices are excluded.

An Enhanced or Premium label describes the installed asset. Some enumerated Siri voices cannot export audio through AVSpeechSynthesizer. If a voice fails, choose another installed natural Siri voice. The app does not silently substitute a different voice.

### Speech speed

Move the slider left for slower speech or right for faster speech. **Default** is the app's starting setting of `0.48`; the supported range is `0.20` through `0.65` in `0.01` steps.

The value is passed to Apple's `AVSpeechUtterance.rate` before audio is generated. It changes the pace of the recorded speech, rather than the audio player's playback speed. These are Apple rate values, not playback multipliers: `0.48` does not mean 0.48× speed.

Slower settings produce longer recordings of the same text, and faster settings produce shorter recordings. The relationship is not linear and can vary by voice and passage.

### Automatic regeneration and playback

Before the first successful generation, changing controls only chooses settings. Click **Generate MP3** to create the first recording.

After success, language, voice, and speed changes regenerate automatically when the text is valid and nonempty. The app waits about 450 milliseconds after the last control change so rapid slider movements combine into one request. Existing playback pauses when an automatic update is scheduled.

Only one render runs at a time. If you change controls during a render, it finishes first, and the app then renders the latest selection. Superseded results are not played. The render label uses the voice that produced the recording.

Editing text alone does not start a new render. Click **Generate MP3** after editing, or change a voice control to generate using the current text. Clearing the text prevents automatic generation. Refreshing the page resets the browser's text, selections, and first-generation state; it does not cancel work already running on the server.

The app attempts to play each new recording. Browser autoplay rules can require pressing Play manually; the MP3 remains available to download.

## Playback and downloads

After generation, use the audio player's play, pause, seek, and volume controls. **Download MP3** saves the current recording, normally with the filename `voice-studio.mp3`. The browser controls the destination and may rename repeated downloads.

Download a version before changing controls if you want to keep it. Automatic generation replaces the recording shown in the player and the download link. The interface is not a recording history browser.

The server keeps at most the latest 20 MP3s in its private temporary session directory. Stopping the CLI deletes that directory. A crash or forced termination can leave temporary files until they are cleaned up separately or by the OS. Files already saved through your browser remain available.

## Device readiness

Open the **Device readiness** tab for macOS version, CPU architecture and cores, installed RAM, free temporary disk space, and ffmpeg status. The small dot beside the tab indicates whether the server reported readiness.

Expand **Requirements & voice setup** for the requirements and instructions for adding voices. If generation is disabled, resolve the displayed blockers and restart the CLI. Voice enumeration and encoder capability are checked at startup; downloading a voice or installing ffmpeg while the CLI is running does not refresh those checks.

There is no imposed CPU, RAM, or GPU minimum. The 256 MiB threshold is a disk safety check, not an Apple hardware requirement or a guarantee that every long render fits.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| macOS or Swift error in Terminal | Check macOS version and install Xcode or Apple Command Line Tools as needed. |
| `Permission denied` when launching | From the project directory, run `chmod +x run.sh`, then retry `./run.sh`. |
| Browser did not open | Open the full URL printed in Terminal, including the fragment token. |
| Session expired or cannot connect | Confirm the CLI is still running. After a restart, use the new full URL. |
| No natural Siri voices | Launch with `./run.sh`. If still empty, download a Siri voice in System Settings under Siri or Apple Intelligence & Siri, then restart. Settings names vary by macOS version. |
| ffmpeg or encoder missing | Install an ffmpeg build with `libmp3lame`, ensure it is executable, and restart. The app searches PATH plus common Homebrew and system binary directories. |
| Insufficient disk space | Free space on the system temporary volume and retry. Restart after resolving readiness blockers. |
| Voice produces no audio or is cancelled by macOS | Choose another installed natural Siri voice and use the source launcher. No substitute voice is used. |
| Synthesis or encoding times out | Shorten the passage and try again. Try another installed voice if needed. |
| Another generation is running | Wait for it to finish. Another tab or API client can occupy the session's single render slot. |
| Audio does not play automatically | Press Play. Your browser may block autoplay after asynchronous rendering. |
| Changing text does not regenerate | Expected behavior: click Generate MP3 or change a voice control after a successful generation. |
| Desired version disappeared from the player | The player shows the latest completed selection. Download versions before changing controls. |
| Need to open the UI on a phone | The layout supports mobile-sized windows, but this server accepts connections only from the same Mac. It does not serve a separate phone over Wi-Fi. |

## Using the local HTTP API

For scripts, start `./run.sh --no-open` and keep that process running. API calls are local to the same Mac and require the session token. A separate remote speech API is not involved.

In another Terminal, set the values from the printed URL. Replace both placeholders; do not include the `/#` prefix in the token:

```sh
export VOICE_STUDIO_BASE='http://127.0.0.1:PORT'
export VOICE_STUDIO_TOKEN='SESSION_TOKEN'
```

### Check readiness and voice identifiers

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $VOICE_STUDIO_TOKEN" \
  "$VOICE_STUDIO_BASE/api/status"
```

The response includes `specs`, `voices`, and `busy`. Choose an exact installed voice ID from `voices`; do not pass the friendly menu name as the API voice value.

### Generate an MP3

This example writes `narration.json` in the current directory. Change the voice ID if Nora is not installed:

```sh
cat > narration.json <<'JSON'
{
  "text": "Hello from Voice Studio. This recording was generated locally.",
  "voice": "com.apple.siri.natural.Nora",
  "rate": 0.48
}
JSON

curl --fail-with-body --silent --show-error --max-time 450 \
  -H "Authorization: Bearer $VOICE_STUDIO_TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary @narration.json \
  "$VOICE_STUDIO_BASE/api/generate"
```

Generation is synchronous: the request returns after synthesis and encoding. A successful JSON response includes `id`, `voice`, and a `download` path such as `/api/audio/OUTPUT_ID`. The response's voice name may use Apple's original numbering; the browser formats friendly names separately.

### Download the audio

Replace `OUTPUT_ID` with the ID returned by generation. This command saves `narration.mp3` in the current directory:

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $VOICE_STUDIO_TOKEN" \
  --output narration.mp3 \
  "$VOICE_STUDIO_BASE/api/audio/OUTPUT_ID"
```

The API requires explicit generation requests. Automatic regeneration and playback are browser UI behavior, not a server subscription.

| Status | Meaning |
| --- | --- |
| 200 | Successful status, generation, or download. |
| 400 | Invalid generation input, content type, voice, or rate. |
| 403 | Missing or wrong session token, untrusted Host, or foreign Origin. |
| 404 | Unknown route or audio ID no longer retained. |
| 409 | Another generation is running. Retry after it finishes. |
| 422 | A caught request-parsing, synthesis, encoding, or file error; read the JSON error. |
| 503 | Readiness requirements are unmet. |

Use `127.0.0.1` as printed rather than replacing it with `localhost`: the server validates the Host header. It also rejects foreign Origin headers and does not enable CORS. Do not expose the server or session token to other users or websites.

## Building and development checks

The supported natural-voice launch mode is `./run.sh`, which executes the Swift source. You can also compile the dependency-free package:

```sh
swift build -c release
.build/release/voice-studio --no-open
```

On the development Mac, an unsigned compiled executable does not expose the same Siri natural voices as source execution. A successful build therefore does not guarantee that generation will be ready. If copying the executable, keep its companion `VoiceStudio_VoiceStudio.bundle` resource directory beside it.

To run the integration smoke test:

```sh
python3 Tests/smoke.py
```

To require Nora explicitly:

```sh
TEST_VOICE_ID=com.apple.siri.natural.Nora python3 Tests/smoke.py
```

The test starts its own source-mode server, exercises authentication and validation, generates real speech, verifies MP3 codec and duration with ffprobe, and shuts down its server. It requires Python 3, ffprobe, the encoder, and usable natural Siri voices. It does not cover every browser interaction.

For the one-line installer, screenshots, and a shorter setup overview, see [README.md](../README.md).
