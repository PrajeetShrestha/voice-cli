#!/bin/sh
set -eu
usage() {
    cat <<'HELP'
Voice Studio — local voiceover studio

Usage: voice-studio <command> [options]

Commands:
  web             Start the local Web UI and open your default browser
  run web         Alias for web
  help            Show this help

Options:
  --no-open       Start the server without opening a browser (web only)
  -h, --help     Show this help

Examples:
  voice-studio web
  voice-studio run web
  voice-studio web --no-open

Keep Terminal open while using the studio. Press Control-C to stop.
Running without arguments also starts the Web UI for compatibility.
HELP
}
case "${1:-}" in
    help|-h|--help) usage; exit 0 ;;
    web) shift ;;
    run)
        shift
        if [ "${1:-}" != web ]; then echo 'Usage: voice-studio run web [--no-open]' >&2; exit 2; fi
        shift ;;
    ''|--no-open) ;;
    *) echo "Unknown command: $1. Run voice-studio --help." >&2; exit 2 ;;
esac
for arg in "$@"; do
    case "$arg" in
        --no-open) ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg. Run voice-studio --help." >&2; exit 2 ;;
    esac
done
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ "$(uname -s)" != Darwin ]; then
    python=${VOICE_STUDIO_KOKORO_PYTHON:-python3}
    exec "$python" Sources/VoiceStudio/kokoro_bridge.py serve "$@"
fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 13 ]; then echo 'Voice Studio requires macOS 13 or newer. Update macOS before running.' >&2; exit 1; fi
if ! xcrun --find swift >/dev/null 2>&1; then echo 'Swift 5.9+ is required to build. Install Xcode or Apple Command Line Tools, then retry.' >&2; exit 1; fi
# On some macOS releases, the Swift runtime sees enhanced Siri voices that
# unsigned standalone binaries cannot enumerate. Use this mode by default.
exec /usr/bin/swift Sources/VoiceStudio/main.swift "$@"
