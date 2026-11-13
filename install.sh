#!/bin/sh
# Install Voice Studio from a tagged GitHub source archive.
set -eu
source_dir=
case "${1:-}" in
    --local) source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd); shift ;;
    --help|-h) printf 'Usage: ./install.sh [--local]\n  --local  Install this checkout instead of the tagged release.\n'; exit 0 ;;
    '') ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac
[ "$#" -eq 0 ] || { echo 'Unexpected arguments.' >&2; exit 2; }

fail() { printf 'Voice Studio: %s\n' "$*" >&2; exit 1; }
os=$(uname -s)
case "$os" in
    Darwin)
        [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || fail 'Update to macOS 13 or newer.'
        xcrun --find swift >/dev/null 2>&1 || fail 'Install Apple Command Line Tools with: xcode-select --install.' ;;
    Linux)
        python=${VOICE_STUDIO_KOKORO_PYTHON:-${VOICE_STUDIO_PYTHON:-python3}}
        "$python" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null || fail 'Python 3.10+ is required on Linux.' ;;
    *) fail 'Only macOS and Linux are supported.' ;;
esac

# Use an existing encoder, or install one with an existing Homebrew installation.
encoder=$(command -v ffmpeg || true)
if [ -z "$encoder" ]; then
    for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
        if [ -x "$candidate" ]; then encoder=$candidate; break; fi
    done
fi
if [ -z "$encoder" ]; then
    brew_bin=$(command -v brew || true)
    if [ -z "$brew_bin" ]; then
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [ -x "$candidate" ]; then brew_bin=$candidate; break; fi
        done
    fi
    [ -n "$brew_bin" ] || fail 'ffmpeg is required. Install Homebrew from https://brew.sh, run brew install ffmpeg, then rerun this installer.'
    printf 'Installing ffmpeg with Homebrew…\n'
    "$brew_bin" install ffmpeg
    encoder=$("$brew_bin" --prefix)/bin/ffmpeg
fi
"$encoder" -hide_banner -encoders 2>/dev/null | /usr/bin/grep -q libmp3lame || fail 'Your ffmpeg build must include libmp3lame.'

install_root=${VOICE_STUDIO_INSTALL_ROOT:-"$HOME/.local/share/voice-studio"}
bin_dir=${VOICE_STUDIO_BIN_DIR:-"$HOME/.local/bin"}
release_ref=${VOICE_STUDIO_REF:-v0.2.0}
case "$install_root:$bin_dir" in *'
'*) fail 'Installation paths cannot contain newlines.' ;; esac
staging=$(mktemp -d "${TMPDIR:-/tmp}/voice-studio-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
if [ -n "$source_dir" ]; then
    printf 'Installing Voice Studio from this checkout…\n'
else
printf 'Downloading Voice Studio %s…\n' "$release_ref"
curl --fail --silent --show-error --location \
    "https://github.com/PrajeetShrestha/voice-cli/archive/refs/tags/$release_ref.tar.gz" \
    --output "$staging/source.tar.gz"
mkdir "$staging/source"
tar -xzf "$staging/source.tar.gz" -C "$staging/source" --strip-components=1
    source_dir="$staging/source"
fi
[ -f "$source_dir/Sources/VoiceStudio/main.swift" ] || fail 'The downloaded archive is missing application sources.'
mkdir -p "$install_root/Sources/VoiceStudio" "$install_root/scripts" "$bin_dir"
cp "$source_dir/Sources/VoiceStudio/main.swift" "$install_root/Sources/VoiceStudio/main.swift"
cp "$source_dir/Sources/VoiceStudio/index.html" "$install_root/Sources/VoiceStudio/index.html"
if [ -f "$source_dir/Sources/VoiceStudio/kokoro_bridge.py" ]; then cp "$source_dir/Sources/VoiceStudio/kokoro_bridge.py" "$install_root/Sources/VoiceStudio/"; fi
cp "$source_dir/run.sh" "$install_root/run.sh"
cp "$source_dir/VERSION" "$install_root/VERSION"
cp "$source_dir/scripts/narrate.py" "$install_root/scripts/narrate.py"
chmod +x "$install_root/run.sh"
# Quote the installation path for the generated POSIX shell launcher.
escaped_root=$(printf '%s' "$install_root" | sed "s/'/'\\\\''/g")
printf '#!/bin/sh\nexec '\''%s/run.sh'\'' "$@"\n' "$escaped_root" > "$staging/voice-studio"
chmod +x "$staging/voice-studio"
cp "$staging/voice-studio" "$bin_dir/voice-studio"
printf '\nVoice Studio installed.\nStart the web UI with:\n  %s/voice-studio web\n' "$bin_dir"
case ":$PATH:" in
    *":$bin_dir:"*) printf 'Or run: voice-studio web\n' ;;
    *) printf '\nTo use the short command, add this directory to PATH in your shell profile:\n  %s\n' "$bin_dir" ;;
esac
printf '\nOn macOS, download a natural Siri voice in System Settings if needed.\nOn Linux, install Kokoro in a separate Python environment to generate audio.\nSee README for setup. Run the installer again to reinstall this release.\n'
