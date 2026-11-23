#!/usr/bin/env bash
# Runs one investigation in the scratch copy made by setup.sh, at a fixed 1/30 s step.
# usage: SIM=/path/to/scratch GODOT=/path/to/godot run.sh arena <spec.json> <out.jsonl>
#        ... run.sh match <spec.json> <out.json>
#        ... run.sh rates <cyborg|knights|knights_keep>      (RATES_SPEED=1.3 tries a road bonus)
#        ... run.sh pace
set -euo pipefail
SIM="${SIM:?scratch copy made by setup.sh}"
GODOT="${GODOT:-godot}"
run() { "$GODOT" --headless --fixed-fps 30 --path "$SIM" --script "res://balance/$1"; }
case "${1:-}" in
  arena) ARENA_SPEC="$(realpath "$2")" ARENA_OUT="$(realpath -m "$3")" run arena.gd ;;
  match) MATCH_SPEC="$(realpath "$2")" MATCH_OUT="$(realpath -m "$3")" run match2.gd ;;
  rates) RATES_MODE="$2" run rates.gd ;;
  pace) run pace_check.gd ;;
  *) sed -n 2,7p "$0"; exit 2 ;;
esac
