#!/bin/sh
# Install Voice Studio from a tagged GitHub source archive.
set -eu

fail() { printf 'Voice Studio: %s\n' "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail 'macOS 13 or newer is required.'
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || fail 'Update to macOS 13 or newer.'
xcrun --find swift >/dev/null 2>&1 || fail 'Install Apple Command Line Tools with: xcode-select --install. Then rerun this installer.'

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
release_ref=${VOICE_STUDIO_REF:-v0.1.0}
case "$install_root:$bin_dir" in *'
'*) fail 'Installation paths cannot contain newlines.' ;; esac
staging=$(mktemp -d "${TMPDIR:-/tmp}/voice-studio-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
printf 'Downloading Voice Studio %s…\n' "$release_ref"
curl --fail --silent --show-error --location \
    "https://github.com/PrajeetShrestha/voice-cli/archive/refs/tags/$release_ref.tar.gz" \
    --output "$staging/source.tar.gz"
mkdir "$staging/source"
tar -xzf "$staging/source.tar.gz" -C "$staging/source" --strip-components=1
[ -f "$staging/source/Sources/VoiceStudio/main.swift" ] || fail 'The downloaded archive is missing application sources.'
mkdir -p "$install_root/Sources/VoiceStudio" "$install_root/scripts" "$bin_dir"
cp "$staging/source/Sources/VoiceStudio/main.swift" "$install_root/Sources/VoiceStudio/main.swift"
cp "$staging/source/Sources/VoiceStudio/index.html" "$install_root/Sources/VoiceStudio/index.html"
cp "$staging/source/run.sh" "$install_root/run.sh"
cp "$staging/source/scripts/narrate.py" "$install_root/scripts/narrate.py"
chmod +x "$install_root/run.sh"
# Quote the installation path for the generated POSIX shell launcher.
escaped_root=$(printf '%s' "$install_root" | sed "s/'/'\\\\''/g")
printf '#!/bin/sh\nexec '\''%s/run.sh'\'' "$@"\n' "$escaped_root" > "$staging/voice-studio"
chmod +x "$staging/voice-studio"
cp "$staging/voice-studio" "$bin_dir/voice-studio"
printf '\nVoice Studio installed.\nStart the web UI with:\n  %s/voice-studio\n' "$bin_dir"
case ":$PATH:" in
    *":$bin_dir:"*) printf 'Or run: voice-studio\n' ;;
    *) printf '\nTo use the short command, add this directory to PATH in your shell profile:\n  %s\n' "$bin_dir" ;;
esac
printf '\nDownload a natural Siri voice in System Settings if needed.\nRun the installer again to reinstall this release.\n'
