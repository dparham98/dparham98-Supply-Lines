#!/usr/bin/env bash
# Installs the pinned Godot editor (Linux x86_64) and verifies its SHA-512.
# usage: ci/install_godot.sh [install-dir]   (default: $HOME/.local/godot)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/.godot-version")"
# SHA-512 from https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt
SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
[ "$VERSION" = "4.7.2-stable" ] || { echo "Update SHA512 in ci/install_godot.sh for $VERSION" >&2; exit 1; }
DEST="${1:-$HOME/.local/godot}"
ZIP="Godot_v${VERSION}_linux.x86_64.zip"
BIN="$DEST/Godot_v${VERSION}_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  curl -fsSL -o "$DEST/$ZIP" "https://github.com/godotengine/godot/releases/download/${VERSION}/${ZIP}"
  echo "$SHA512  $DEST/$ZIP" | sha512sum -c -
  unzip -oq "$DEST/$ZIP" -d "$DEST"
  rm "$DEST/$ZIP"
  chmod +x "$BIN"
fi
"$BIN" --headless --version
echo "$BIN"
