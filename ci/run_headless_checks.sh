#!/usr/bin/env bash
# Headless validation: editor import, main-scene startup and every tests/*_test.gd suite.
# A suite passes only with exit code 0, no "SCRIPT ERROR"/"ERROR:" lines and a *_PASSED marker.
# This does NOT verify rendering, visuals, input feel or performance.
# usage: GODOT=/path/to/godot ci/run_headless_checks.sh [log-dir]
# Test results/screenshots go to $SUPPLY_LINES_TEST_OUTPUT (default: <log-dir>/output).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOGS="${1:-$ROOT/ci-logs}"
SUITE_LIMIT=600     # seconds per suite before it is reported as TIMEOUT
IMPORT_LIMIT=900
SCRIPT_ERROR_GRACE=15  # a SceneTree script stops at a script error and never quits; stop it after this
# scene_setup_test rebuilds this generated scene and restores it; the runner verifies that.
GENERATED="scenes/maps/terrain_landmarks.tscn"
# Result files the headless suites must produce.
REQUIRED_OUTPUTS="camera_work/camera_results.json gameplay_work/skirmish_results.json camera_work/terrain_test_results.json camera_work/scene_setup_results.json"

mkdir -p "$LOGS"
LOGS="$(cd "$LOGS" && pwd)"
export SUPPLY_LINES_TEST_OUTPUT="${SUPPLY_LINES_TEST_OUTPUT:-$LOGS/output}"
rm -rf "$SUPPLY_LINES_TEST_OUTPUT"
cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree is not clean; commit or stash changes first:" >&2; git status --short >&2; exit 2
fi

SUMMARY="$LOGS/summary.md"
printf '| Check | Result | Exit | Seconds |\n| --- | --- | --- | --- |\n' > "$SUMMARY"
failed=0

# run_check <name> <limit> <needs-marker> <godot args...>
run_check() {
  local name="$1" limit="$2" needs_marker="$3"; shift 3
  local log="$LOGS/$name.log" start elapsed first_error=-1 stopped=""
  echo "::group::$name"
  echo "RUN $name"
  start=$(date +%s)
  "$GODOT" "$@" > "$log" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$limit" ]; then stopped="timeout"; kill "$pid" 2>/dev/null; break; fi
    if [ "$first_error" -lt 0 ] && grep -q 'SCRIPT ERROR' "$log"; then first_error=$elapsed; fi
    if [ "$first_error" -ge 0 ] && [ $(( elapsed - first_error )) -ge "$SCRIPT_ERROR_GRACE" ]; then
      stopped="script-error"; kill "$pid" 2>/dev/null; break
    fi
    sleep 1
  done
  wait "$pid"; local rc=$?
  local seconds=$(( $(date +%s) - start ))
  local result=PASS
  if [ "$stopped" = timeout ]; then result="TIMEOUT (>${limit}s)"
  elif grep -qE 'TEST_OUTPUT_ERROR|LANDMARKS_RESTORE_FAILED' "$log"; then result=OUTPUT_ERROR
  elif grep -q 'Assertion failed' "$log"; then result=ASSERTION_FAILED
  elif grep -q 'SCRIPT ERROR' "$log"; then result=SCRIPT_ERROR
  elif [ "$rc" -ne 0 ]; then result=NONZERO_EXIT
  elif grep -q '^ERROR:' "$log"; then result=ENGINE_ERROR
  elif [ "$needs_marker" = yes ] && ! grep -q '_PASSED' "$log"; then result=NO_PASS_MARKER
  fi
  [ -n "$stopped" ] && [ "$stopped" = script-error ] && result="$result (stopped after hang)"
  echo "$result $name rc=$rc ${seconds}s"
  if [ "$result" != PASS ]; then failed=$((failed+1)); grep -nE -B2 -A6 'SCRIPT ERROR|^ERROR:|TEST_OUTPUT_ERROR|LANDMARKS_RESTORE_FAILED' "$log" | head -60; tail -20 "$log"; fi
  echo "::endgroup::"
  printf '| %s | %s | %s | %s |\n' "$name" "$result" "$rc" "$seconds" >> "$SUMMARY"
}

run_check import "$IMPORT_LIMIT" no --headless --path . --import
run_check main_scene "$SUITE_LIMIT" no --headless --path . --quit-after 120
for t in tests/*_test.gd; do
  run_check "$(basename "$t" .gd)" "$SUITE_LIMIT" yes --headless --path . --script "res://$t"
done

for f in $REQUIRED_OUTPUTS; do
  if [ -s "$SUPPLY_LINES_TEST_OUTPUT/$f" ]; then r=PASS; else r=MISSING; failed=$((failed+1)); fi
  echo "$r output $f"; printf '| output %s | %s | | |\n' "$f" "$r" >> "$SUMMARY"
done

dirty="$(git status --porcelain)"
if [ -n "$dirty" ]; then
  echo "FAIL checkout left dirty by tests:"; echo "$dirty"; failed=$((failed+1))
  printf '| clean checkout | DIRTY | | |\n' >> "$SUMMARY"
  git checkout -- "$GENERATED" 2>/dev/null
else
  echo "PASS checkout clean"; printf '| clean checkout | PASS | | |\n' >> "$SUMMARY"
fi

echo; cat "$SUMMARY"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && { echo "## Headless validation"; cat "$SUMMARY"; } >> "$GITHUB_STEP_SUMMARY"
echo "failures=$failed"
[ "$failed" -eq 0 ]
