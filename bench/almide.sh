#!/usr/bin/env bash
# Almide: a language the model has certainly never seen.
#
# Every other benchmark here is contaminated. Python, Go, Rust, C++ and
# JavaScript are in the training data, and so are the Exercism problems
# themselves — a model can score well on `hamming` by recalling it. Almide
# is one person's language, and its exercises live in a private repo.
# Nothing here can be recalled; it has to be read.
#
# So this measures the actual claim of the project. famulus5's premise is
# that observing beats guessing. If that is true, a cheap model with a
# 949-line cheatsheet in front of it should be able to write a language it
# has never met. If it is false, this is where it shows.
#
# The exercises ship with a reference result to compare against:
# research/benchmark/exercises/BENCHMARK.md records Claude solving 14 of
# them at 248/248 assertions, given the same cheatsheet and no other help.
#
#   ALMIDE=/path/to/almide-repo bench/almide.sh
#   BENCH_LIMIT=5 BENCH_JOBS=3 bench/almide.sh
#   bench/almide.sh hamming bob        just these exercises

set -uo pipefail

AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALMIDE="${ALMIDE:-$HOME/workspace/github.com/almide/almide}"
EXDIR="$ALMIDE/research/benchmark/exercises"
CHEAT="$ALMIDE/docs/CHEATSHEET.md"
WORK="${BENCH_WORK:-${TMPDIR:-/tmp}/mendide-almide}"
LIMIT="${BENCH_LIMIT:-0}"
JOBS="${BENCH_JOBS:-3}"
ATTEMPTS="${BENCH_ATTEMPTS:-6}"
# BENCH_AGENT=1 runs the tool loop (--agent) instead of the fixed
# observe-then-edit pass, so the two can be compared on the same problems.
AGENT="${BENCH_AGENT:-}"
STEPS="${BENCH_STEPS:-20}"

command -v almide >/dev/null || { echo "almide not on PATH" >&2; exit 2; }
[ -d "$EXDIR" ] || { echo "exercises not found at $EXDIR" >&2; exit 2; }
[ -f "$CHEAT" ] || { echo "CHEATSHEET.md not found at $CHEAT" >&2; exit 2; }

# Keep the tests, drop the implementation.
#
# The tests are the specification and stay verbatim; every `fn` line is
# removed along with its body. What is left will not compile — the tests
# call functions that no longer exist — which is exactly the baseline
# famulus5 should be reading.
strip_impl() {
  python3 - "$1" "$2" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().split("\n")
out, sigs = [], []
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r'^(effect )?fn ', line):
        sigs.append(re.sub(r'\s*=.*$', '', line).strip())
        # A body is either the rest of this line, or a brace block that
        # ends at the first line starting with an unindented '}'.
        if line.rstrip().endswith("{"):
            i += 1
            while i < len(lines) and not lines[i].startswith("}"):
                i += 1
        i += 1
        continue
    out.append(line)
    i += 1
open(dst, "w").write("\n".join(out).strip() + "\n")
sys.stderr.write("\n".join(sigs))
PY
}

run_one() {
  local ex=$1
  local srcfile; srcfile=$(ls "$EXDIR/$ex"/*.almd 2>/dev/null | head -1)
  [ -z "$srcfile" ] && return 0
  local base; base=$(basename "$srcfile")
  local d="$WORK/$ex"

  rm -rf "$d"; mkdir -p "$d"
  cp "$CHEAT" "$d/CHEATSHEET.md"
  local sigs; sigs=$(strip_impl "$srcfile" "$d/$base" 2>&1 >/dev/null)
  ( cd "$d" && git init -q && git add -A \
      && git -c user.email=b@b -c user.name=b commit -qm stub ) >/dev/null 2>&1

  local task="Implement the missing functions in $base so that every test in it passes.

The language is Almide. You have almost certainly never seen it, and
guessing its syntax from another language will not work. CHEATSHEET.md in
this directory is the complete reference — read it before writing anything.

Write these exact signatures, and do not change the test blocks:

$sigs"

  local log="$WORK/$ex.log"
  local mode=(--attempts "$ATTEMPTS")
  [ -n "$AGENT" ] && mode=(--agent --steps "$STEPS")
  # `almide test` with no argument needs an almide.toml, which an exercise
  # directory does not have: under 0.62 it exits 1 without running anything.
  # Naming the file is what actually runs the tests.
  local vc="almide test $base"
  ( "$AGENT_ROOT/mendide" solve "$task" --root "$d" --verify "$vc" "${mode[@]}" ) > "$log" 2>&1

  local result=FAIL
  if ( cd "$d" && almide test "$base" ) >/dev/null 2>&1; then result=PASS; fi

  local cost attempts read_cheat
  cost=$(grep -oE '\$[0-9]+\.[0-9]+' "$log" | tail -1 | tr -d '$'); [ -z "$cost" ] && cost=0
  if [ -n "$AGENT" ]; then
    attempts=$(grep -oE 'in [0-9]+ step' "$log" | grep -oE '[0-9]+' | tail -1)
  else
    attempts=$(grep -c '^\[edit\]' "$log" 2>/dev/null | tr -d '\n ')
  fi; [ -z "$attempts" ] && attempts=0
  # Did it choose to read the reference? That is the whole thesis, and it
  # is a decision the agent makes, not one the harness makes for it.
  if grep -q 'reading:.*CHEATSHEET' "$log"; then read_cheat=yes; else read_cheat=no; fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$ex" "$result" "$attempts" "$cost" "$read_cheat" \
    >> "$WORK/results.tsv"
  printf '%-22s %-6s cheatsheet-read=%s\n' "$ex" "$result" "$read_cheat"
}
export -f run_one strip_impl
export EXDIR CHEAT WORK AGENT_ROOT ATTEMPTS AGENT STEPS

mkdir -p "$WORK"; : > "$WORK/results.tsv"

# Prove the harness. The untouched exercise must pass and the stripped one
# must fail; a harness that cannot tell those apart reports a number that
# means nothing.
echo "== harness check =="
probe=$(ls "$EXDIR" | grep -vE 'BENCHMARK|run_exercise|wasm-smoke|json-config' | head -1)
probe_src=$(ls "$EXDIR/$probe"/*.almd | head -1)
for mode in original stripped; do
  d="$WORK/_check/$mode"; rm -rf "$d"; mkdir -p "$d"
  if [ "$mode" = original ]; then
    cp "$probe_src" "$d/"
  else
    strip_impl "$probe_src" "$d/$(basename "$probe_src")" 2>/dev/null
  fi
  ( cd "$d" && almide test "$(basename "$probe_src")" ) >/dev/null 2>&1
  code=$?
  printf '  %-16s %-10s exit=%d\n' "$probe" "$mode" "$code"
  # A harness that cannot tell a working exercise from a stubbed one
  # reports a number that means nothing. Assert, do not print and continue.
  if [ "$mode" = original ] && [ "$code" -ne 0 ]; then
    echo "  the untouched exercise does not pass — the harness is broken" >&2; exit 2
  fi
  if [ "$mode" = stripped ] && [ "$code" -eq 0 ]; then
    echo "  the stripped exercise passes — the harness proves nothing" >&2; exit 2
  fi
done
echo

echo "== running (almide $(almide --version | awk '{print $2}'), $([ -n "$AGENT" ] && echo "agent tool-loop, $STEPS steps" || echo "fixed pass, $ATTEMPTS attempts")) =="
if [ "$#" -gt 0 ]; then
  exercises=$(printf '%s\n' "$@")
else
  exercises=$(ls "$EXDIR" | grep -vE 'BENCHMARK|run_exercise')
  # wasm-smoke has no test blocks, so nothing could decide success there.
  exercises=$(printf '%s\n' "$exercises" | grep -v '^wasm-smoke$')
  # json-config tests the stdlib json module and defines no functions of
  # its own, so the stripped file still passes. Nothing to measure, and
  # pointing an agent at an already-green project is its own hazard.
  exercises=$(printf '%s\n' "$exercises" | grep -v '^json-config$')
  [ "$LIMIT" -gt 0 ] && exercises=$(printf '%s\n' "$exercises" | head -"$LIMIT")
fi
printf '%s\n' "$exercises" | xargs -P "$JOBS" -I{} bash -c 'run_one "$0"' {}

echo
echo "== results =="
python3 - "$WORK/results.tsv" <<'PY'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
p = sum(r[1] == "PASS" for r in rows)
n = len(rows)
cost = sum(float(r[3] or 0) for r in rows)
read = sum(r[4] == "yes" for r in rows)
print(f"solved              {p}/{n}  ({p / n * 100:.1f}%)" if n else "no results")
print(f"cost                ${cost:.4f}")
print(f"read the cheatsheet {read}/{n}")
if n:
    won = [r for r in rows if r[1] == "PASS"]
    from collections import Counter
    print("solved on attempt  ", dict(sorted(Counter(r[2] for r in won).items())))
    bad = [r[0] for r in rows if r[1] == "FAIL"]
    if bad:
        print("failed:            ", ", ".join(bad))
PY
echo "logs: $WORK/<exercise>.log"
