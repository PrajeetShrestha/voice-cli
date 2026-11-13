# Voice Studio architecture

## Project purpose

Voice Studio is a macOS-only local narration tool. A Swift CLI opens a browser UI where users enter text, choose an installed natural Siri voice and speech rate, then generate, preview, and download an MP3. Speech synthesis runs locally through Apple's AVFoundation; ffmpeg encodes the result. There is no cloud service, account, API key, database, or JavaScript build pipeline.

The application requires macOS 13+, Swift 5.9+, an installed voice whose identifier begins with `com.apple.siri.natural.`, ffmpeg with `libmp3lame`, and at least 256 MiB free on the temporary volume. Python and ffprobe are used only by the integration test.

## Repository map

- `run.sh`: checks macOS and Swift availability, changes to the project directory, and runs the Swift source. Passes CLI arguments through.
- `Package.swift`: dependency-free Swift package defining the `voice-studio` executable and copying `index.html` as a resource.
- `Sources/VoiceStudio/main.swift`: application startup, voice discovery, readiness checks, HTTP parsing/routing, speech rendering, encoding, temporary storage, and shutdown.
- `Sources/VoiceStudio/index.html`: self-contained browser interface with inline CSS and vanilla JavaScript. Handles readiness, language and voice selection, text input, generation, playback, and downloads.
- `Tests/smoke.py`: integration test that launches the CLI, exercises HTTP/security/input handling and concurrent rendering, and verifies generated MP3s with ffprobe.
- `install.sh`: macOS source installer and launcher setup.
- `scripts/narrate.py`: Python helper for local agent narration and server lifecycle management.
- `demo/`: illustrated chapter frames, narration script, and video builder.
- `README.md` and `docs/`: installation, usage, architecture, and agent guides.

## Architecture and data flow

1. The CLI creates a private temporary session directory and random bearer token, locates ffmpeg, checks its encoder support, and enumerates natural Siri voices.
2. A small HTTP server built directly on Darwin sockets binds to `127.0.0.1` on an OS-assigned port. The CLI prints a URL containing the token in its fragment and opens it unless `--no-open` is supplied.
3. The browser stores the fragment token in `sessionStorage`, removes the fragment from the address bar, and sends the token in Authorization headers. It loads device readiness and the voice catalog from `/api/status`.
4. The browser posts text, an exact voice identifier, and rate to `/api/generate`. The server validates the request, checks readiness, and reserves the single generation slot.
5. A `Renderer` starts `AVSpeechSynthesizer` on the main run loop. PCM callbacks write a CAF file through `AVAudioFile`; delegate completion or a timeout finishes the render.
6. The request handler waits for rendering, then launches ffmpeg with an argument array to encode the CAF into MP3. The CAF is removed afterward.
7. The server returns an output ID and download path. The browser fetches the MP3 with authorization and creates a blob URL for native audio playback and download.

### HTTP interface

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | Serve the HTML interface; bearer token not required. |
| GET | `/api/status` | Return device specs, readiness blockers, installed voices, and busy state. |
| POST | `/api/generate` | Accept JSON `{text, voice, rate}` and return `{id, voice, download}`. |
| GET | `/api/audio/<id>` | Return a retained MP3 by server-generated ID. |

All requests undergo Host and Origin checks; API routes require the session bearer token. Invalid generation input returns 400, overlapping generation returns 409, unmet requirements return 503, and render/encoding or other caught errors return 422.

### Concurrency and lifecycle

- A background accept loop dispatches up to eight HTTP handlers. `stateLock` protects the busy flag and retained output IDs; only one generation runs at a time.
- Speech startup and completion use the main run loop. `Renderer` locks PCM writes and completion state, and the request handler waits on a semaphore. Preserve the renderer's lifetime through delegate completion. Do not introduce a nested main-queue run loop, which can stall delegate delivery.
- Synthesis has a five-minute timeout; encoding has a two-minute timeout. Closing or reloading the browser does not cancel generation.
- Session files live in a randomly named temporary directory with mode `0700`. Only the latest 20 MP3s are retained. SIGINT/SIGTERM remove the session directory and exit; crashes or forced termination can leave files behind.

## Constraints to preserve

- Keep the server local to loopback. Preserve bearer authentication, Host/Origin validation, restrictive CSP, no CORS, request bounds, and no-store responses.
- Never interpolate user input into shell commands or accept filesystem paths for downloads. Execute ffmpeg using `Process` arguments and resolve audio only through retained server-generated IDs.
- Accept nonblank plain Unicode text up to 10,000 Swift characters, JSON bodies up to 65,536 bytes, and finite rates from 0.20 through 0.65. Browser `maxlength` measures UTF-16 code units, so its limit differs for some Unicode input.
- Offer only installed natural Siri voices. Do not silently substitute voices or download assets. Nora (`com.apple.siri.natural.Nora`) is preferred when available and labeled “Nora”; it is distinct from the Norwegian system voice named Nora. Some enumerated voices cannot export audio and must report failure.
- Keep unmet runtime requirements visible in the browser with generation disabled. Do not automatically install ffmpeg or voice assets.
- Support both HTML resource lookup modes: source-relative when interpreted, `Bundle.module` when built with SwiftPM.

## Running and verification

```sh
./run.sh                         # Supported launch mode; opens browser
./run.sh --no-open               # Print URL without opening browser
swift build -c release          # Compile the package
python3 Tests/smoke.py           # Full integration test using Swift source
TEST_VOICE_ID=com.apple.siri.natural.Nora python3 Tests/smoke.py
TEST_COMPILED=1 python3 Tests/smoke.py  # Requires built release executable
```

The source launch is intentional: on the development Mac, unsigned compiled binaries do not expose the same natural Siri voices. A successful package build does not establish voice availability. Compiled execution also needs the companion `VoiceStudio_VoiceStudio.bundle` resource directory. If SwiftPM's nested sandbox is unavailable in automation, use `swift build --disable-sandbox -c release`.

For behavior changes, use the smoke test when the machine has the required voice and encoder assets. It generates real audio and requires readiness to pass. Keep README instructions and the browser/server contract aligned with changes. Documentation-only edits do not require audio generation. The separate installer can install ffmpeg through an existing Homebrew installation; the running CLI does not install dependencies.

## Optional Kokoro and Linux extension

The latest source is no longer macOS-only. `kokoro_bridge.py`, packaged alongside
the HTML, supplies a 54-voice catalog, import-spec detection, CPU synthesis and a
portable loopback HTTP server. On macOS, Swift retains Siri and launches the bridge
in the configured Python for Kokoro; on Linux `run.sh` launches the Python server.
No packages or models are installed during startup. The server status has an
`engines` array; existing `voices` remains Siri-only. Kokoro requests carry
`engine: kokoro`, a catalog voice ID, speed 0.5–2.0 and an explicit `allowDownloads`
boolean. Default offline mode prohibits model downloads and reports missing assets.
See README for setup, dependency and version details. UI options are engine-specific.
Model readiness is not inferred from package detection. Each render uses a bounded
subprocess (300 seconds synthesis, 120 seconds encoding), and only one runs at once.
The portable backend uses the same HTML and security contract; its HTTP workers
are capped at eight. Mac Siri export still depends on OS-provided voice access.
