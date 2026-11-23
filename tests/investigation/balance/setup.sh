#!/usr/bin/env bash
# Builds the scratch copy the balance investigation runs in. It never changes this checkout.
# usage: GODOT=/path/to/godot tests/investigation/balance/setup.sh /path/to/scratch
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SIM="${1:?scratch directory}"
GODOT="${GODOT:-godot}"
mkdir -p "$SIM"
git -C "$ROOT" archive HEAD | tar -x -C "$SIM" --exclude=Blender --exclude=tests/investigation
(cd "$SIM" && patch -p1 --no-backup-if-mismatch < "$HERE/prototype.patch")
mkdir -p "$SIM/balance"
cp "$HERE"/scripts/* "$SIM/balance/"
"$GODOT" --headless --path "$SIM" --import > "$SIM/import.log" 2>&1
echo "Scratch copy ready in $SIM"
