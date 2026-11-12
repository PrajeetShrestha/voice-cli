#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ "$(uname -s)" != Darwin ]; then echo 'Voice Studio requires macOS 13 or newer. Linux and Windows cannot use AVSpeechSynthesizer.' >&2; exit 1; fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 13 ]; then echo 'Voice Studio requires macOS 13 or newer. Update macOS before running.' >&2; exit 1; fi
if ! xcrun --find swift >/dev/null 2>&1; then echo 'Swift 5.9+ is required to build. Install Xcode or Apple Command Line Tools, then retry.' >&2; exit 1; fi
# On some macOS releases, the Swift runtime sees enhanced Siri voices that
# unsigned standalone binaries cannot enumerate. Use this mode by default.
exec /usr/bin/swift Sources/VoiceStudio/main.swift "$@"
