#!/usr/bin/env bash
# Headless validation: editor import, main-scene startup and every tests/*_test.gd suite.
# A suite passes only with exit code 0, no "SCRIPT ERROR"/"ERROR:" lines and a *_PASSED marker.
# This does NOT verify rendering, visuals, input feel or performance.
# usage: GODOT=/path/to/godot ci/run_headless_checks.sh [log-dir]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOGS="${1:-$ROOT/ci-logs}"
# scene_setup_test rewrites this generated scene; it runs last and the file is restored afterwards.
GENERATED="scenes/maps/terrain_landmarks.tscn"
mkdir -p "$LOGS"
cd "$ROOT"
if ! git diff --quiet -- "$GENERATED"; then
  echo "$GENERATED has uncommitted changes; commit or stash them first." >&2; exit 2
fi
errors() { grep -cE 'SCRIPT ERROR|^ERROR:' "$1"; }
failed=0

echo "::group::Editor import"
timeout 900 "$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1; rc=$?
e=$(errors "$LOGS/import.log"); echo "import rc=$rc errors=$e"; cat "$LOGS/import.log"
echo "::endgroup::"
[ $rc -eq 0 ] && [ "$e" -eq 0 ] || failed=$((failed+1))

timeout 300 "$GODOT" --headless --path . --quit-after 120 > "$LOGS/main_scene.log" 2>&1; rc=$?
e=$(errors "$LOGS/main_scene.log"); echo "main scene startup rc=$rc errors=$e"
[ $rc -eq 0 ] && [ "$e" -eq 0 ] || { failed=$((failed+1)); cat "$LOGS/main_scene.log"; }

suites=$(ls tests/*_test.gd | grep -v scene_setup_test; echo tests/scene_setup_test.gd)
for t in $suites; do
  n=$(basename "$t" .gd)
  timeout 600 "$GODOT" --headless --path . --script "res://$t" > "$LOGS/$n.log" 2>&1; rc=$?
  e=$(errors "$LOGS/$n.log")
  if [ $rc -eq 0 ] && [ "$e" -eq 0 ] && grep -qE '_PASSED' "$LOGS/$n.log"; then
    echo "PASS $n"
  else
    echo "FAIL $n (rc=$rc errors=$e)"; failed=$((failed+1)); tail -40 "$LOGS/$n.log"
  fi
done
git checkout -- "$GENERATED"

echo "failures=$failed"
[ $failed -eq 0 ]
