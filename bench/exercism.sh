#!/usr/bin/env bash
# Aider's polyglot benchmark: 225 Exercism problems across six languages.
#
# Unlike bench/polyglot.sh, none of this is ours. The problems, the tests
# and the difficulty were chosen by someone else, and there is a public
# leaderboard to be measured against — which is the point. A benchmark
# you wrote yourself tells you your code runs; this one tells you whether
# it is any good.
#
# Setup:
#   git clone https://github.com/Aider-AI/polyglot-benchmark
#   POLYGLOT=/path/to/polyglot-benchmark bench/exercism.sh python
#
#   bench/exercism.sh python rust go     languages to run
#   BENCH_LIMIT=10                       first N exercises per language
#   BENCH_JOBS=4                         exercises in parallel
#   BENCH_CHECK_ONLY=1                   prove the harness, run nothing
#   BENCH_ONLY=pairs.tsv                 re-run only these "lang<TAB>exercise" rows
#
# The reference solution lives in each exercise's .meta/ directory and is
# deleted before the agent sees anything. Without that the benchmark
# measures nothing at all.

set -uo pipefail

AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLYGLOT="${POLYGLOT:-$AGENT_ROOT/../polyglot-benchmark}"
WORK="${BENCH_WORK:-${TMPDIR:-/tmp}/agent-exercism}"
LIMIT="${BENCH_LIMIT:-0}"
JOBS="${BENCH_JOBS:-4}"
ATTEMPTS="${BENCH_ATTEMPTS:-3}"
# All 47 Java exercises pin Gradle 8.7, which refuses to run on JDK 22 or
# newer. A machine whose default `java` is 25 therefore fails every Java
# exercise at the wrapper, before a test runs, in a way that looks like
# 47 wrong answers. Point Gradle at a 21 if one is installed via mise;
# an explicit JAVA_HOME still wins.
if [ -z "${JAVA_HOME:-}" ] && command -v mise >/dev/null 2>&1; then
  j21="$(mise where java@21 2>/dev/null || true)"
  [ -n "$j21" ] && export JAVA_HOME="$j21"
fi

if [ ! -d "$POLYGLOT" ]; then
  echo "polyglot-benchmark not found at $POLYGLOT" >&2
  echo "  git clone https://github.com/Aider-AI/polyglot-benchmark" >&2
  exit 2
fi

verify_for() {
  case "$1" in
    python)     echo "python3 -m pytest -q" ;;
    rust)       echo "cargo test -q -- --include-ignored" ;;
    go)         echo "go test ./..." ;;
    javascript) echo "npm test" ;;
    # Not -q. Quiet Gradle reports a failure as "20 tests completed, 1
    # failed. See the report at: file://..." — the test's name and the
    # assertion are in an HTML file the model cannot open. Without -q
    # every failing test prints its name and exception; what is filtered
    # is the stack frames and the build-system chatter around them, so
    # the excerpt the model gets is failures, not Gradle. pipefail keeps
    # Gradle's exit status; `|| true` keeps grep's from masking it.
    java)       echo "set -o pipefail; ./gradlew test --console=plain 2>&1 | { grep -vE '^\\s+at |^\\s*$|^> Task|^\\* (What went wrong|Try|Get more help|Exception is)|^> Run with|^> Get more help|BUILD FAILED|--scan|--stacktrace|--info or --debug|^Deprecated|^You can use|^See https://docs.gradle' || true; }" ;;
    # -DEXERCISM_RUN_ALL_TESTS matters: without it the CMakeLists compiles
    # only the first TEST_CASE (1 of 17 on all-your-base), and running the
    # binary through ctest instead of directly reports "No tests were
    # found" while still exiting 0. Either mistake turns this into a
    # does-it-compile check.
    cpp)        echo 'cmake -B build -S . -DEXERCISM_RUN_ALL_TESTS=1 >/dev/null && cmake --build build >/dev/null && ./build/"$(basename "$PWD")"' ;;
    *)          echo "" ;;
  esac
}

# Put the reference solution where the stub is, to prove the harness can
# tell a right answer from a wrong one before it judges anybody.
install_reference() {
  local lang=$1 d=$2
  case "$lang" in
    python) cp "$d"/.meta/example.py \
              "$d/$(basename "$(ls "$d"/*.py | grep -v _test | head -1)")" ;;
    rust)   cp "$d"/.meta/example.rs "$d/src/lib.rs" ;;
    go)     cp "$d"/.meta/example.go "$(ls "$d"/*.go | grep -v _test | head -1)" ;;
    # C++ splits the answer across both the source and the header; copying
    # only the .cpp leaves the stub's declarations and fails to compile,
    # which looks exactly like a harness that cannot tell right from wrong.
    cpp)    local base; base="$(basename "$d" | tr '-' '_')"
            cp "$d"/.meta/example.cpp "$d/$base.cpp"
            [ -f "$d/.meta/example.h" ] && cp "$d"/.meta/example.h "$d/$base.h" ;;
    javascript) cp "$d"/.meta/proof.ci.js \
                  "$d/$(basename "$(ls "$d"/*.js | grep -v '\.spec\.js$' | grep -v '^babel' | head -1)")" ;;
    java)   cp "$d"/.meta/src/reference/java/*.java "$d/src/main/java/" ;;
    *)      return 1 ;;
  esac
}

# What an exercise directory needs before anything runs in it.
#
# Every one of the 49 JavaScript exercises declares the same nine
# devDependencies (verified: one md5 across all package.json files), so
# jest gets a single shared install, symlinked in. Installing per
# exercise would be 49 x 118 MB and 49 x 15 s for identical bytes. The
# symlink is one git entry in the stub commit, and both file walkers
# (observe.ts, the kernel's repo map) already prune node_modules.
prepare_dir() {
  local lang=$1 d=$2
  case "$lang" in
    javascript)
      # The shared install stays where npm put it, under a directory that
      # is literally named node_modules. Node resolves a package's own
      # dependencies by walking up from its real path looking for that
      # name, so a copy moved to "_node_modules" makes jest fail with
      # "Cannot find module 'import-local'" — the module is right there,
      # in a directory Node will not look in.
      local seed="$WORK/_npm-seed"
      if [ ! -d "$seed/node_modules" ]; then
        rm -rf "$seed"; mkdir -p "$seed"
        cp "$d/package.json" "$seed/"; [ -f "$d/.npmrc" ] && cp "$d/.npmrc" "$seed/"
        ( cd "$seed" && npm install --no-audit --no-fund >/dev/null 2>&1 ) \
          || { echo "npm install failed in $seed" >&2; return 1; }
      fi
      ln -s "$seed/node_modules" "$d/node_modules"
      # Exercism ships every test but the first as xtest(); aider's
      # npm-test.sh turns them back on with exactly this substitution.
      perl -pi -e 's/\bxtest\(/test(/g' "$d"/*.spec.js ;;
    java)
      # Same convention, spelled @Disabled("Remove to run test"). Removed
      # with the regex aider's benchmark.py uses, so the same 20 tests run.
      perl -0pi -e 's/\@Disabled\([^)]*\)\s*\n//g' "$d"/src/test/java/*.java ;;
  esac
}

# Skip markers are the benchmark's oldest trap, and this harness fell in.
#
# Exercism marks every test after the first as skipped — #[ignore] in
# Rust, xtest() in JavaScript, @Disabled in Java — and a stub that throws
# fails the one live test while a reference passes it, so "stub fails,
# solution passes" holds with 1 of 20 tests running. Aider's own runner
# re-enables them (--include-ignored, a sed, a regex). Until this file did
# the same, every Java "PASS" meant one test, and every earlier Rust
# number here was a first-test-only number. Counting is the check that
# would have caught it: a reference that runs one test is not a harness.
count_tests() {
  case "$1" in
    python)     grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s+0}' ;;
    rust)       grep -oE 'test result: ok\. [0-9]+ passed' | awk '{s+=$4} END{print s+0}' ;;
    go)         grep -c '^\s*--- PASS' ;;
    cpp)        grep -oE 'in [0-9]+ test cases?' | awk '{s+=$2} END{print s+0}' ;;
    javascript) grep -oE 'Tests:.*' | grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s+0}' ;;
    java)       grep -c ' PASSED$' ;;
    *)          echo 0 ;;
  esac
}
# The verify command, made talkative enough to count. Only the harness
# check uses this; the agent sees the plain command.
counting_command() {
  case "$1" in
    go)   echo "go test -v ./..." ;;
    *)    verify_for "$1" ;;
  esac
}

run_one() {
  local lang=$1 ex=$2
  local src="$POLYGLOT/$lang/exercises/practice/$ex"
  local d="$WORK/$lang/$ex"
  local vc; vc="$(verify_for "$lang")"

  rm -rf "$d"; mkdir -p "$(dirname "$d")"; cp -R "$src" "$d"
  prepare_dir "$lang" "$d"
  # The answer key. Deleting it is the whole integrity of the benchmark.
  rm -rf "$d/.meta"
  ( cd "$d" && git init -q && git add -A \
      && git -c user.email=b@b -c user.name=b commit -qm stub ) >/dev/null 2>&1

  local task; task="$(cat "$d/.docs/instructions.md" 2>/dev/null)"
  if [ -f "$d/.docs/instructions.append.md" ]; then
    task="$task

$(cat "$d/.docs/instructions.append.md")"
  fi
  task="$(printf '%s' "$task" | head -c 6000)"

  local log="$WORK/$lang/$ex.log"
  ( "$AGENT_ROOT/agent" solve "$task" \
      --root "$d" --verify "$vc" --attempts "$ATTEMPTS" ) > "$log" 2>&1

  # The agent's own verdict is not the verdict. Re-run the suite here —
  # under a deadline. An implementation that loops forever (rust/robot-name
  # produced one: unique-name generation that never terminates) hung this
  # line for 1h37m while the agent's own verify had correctly given up at
  # 120s. macOS has no `timeout`; perl's alarm is everywhere.
  local result=FAIL
  if ( cd "$d" && perl -e 'alarm shift; exec @ARGV' 300 bash -c "$vc" ) >/dev/null 2>&1; then result=PASS; fi

  local cost wall attempts
  cost=$(grep -oE '\$[0-9]+\.[0-9]+' "$log" | tail -1 | tr -d '$'); [ -z "$cost" ] && cost=0
  wall=$(grep -oE '[0-9]+s$' "$log" | tail -1); [ -z "$wall" ] && wall="?"
  attempts=$(grep -c '^\[edit\]' "$log" 2>/dev/null | tr -d '\n '); [ -z "$attempts" ] && attempts=0

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$lang" "$ex" "$result" "$attempts" "$cost" "$wall" \
    >> "$WORK/results.tsv"
  printf '%-11s %-28s %s\n' "$lang" "$ex" "$result"
}
export -f run_one verify_for prepare_dir count_tests counting_command
export POLYGLOT WORK AGENT_ROOT ATTEMPTS JAVA_HOME

mkdir -p "$WORK"; [ -n "${BENCH_ONLY:-}" ] || : > "$WORK/results.tsv"

# Prove the harness before trusting it: the reference solution must pass
# and the untouched stub must fail. A harness that cannot tell those
# apart will happily report a number that means nothing.
echo "== harness check =="
for lang in "$@"; do
  ex="$(ls "$POLYGLOT/$lang/exercises/practice" 2>/dev/null | head -1)"
  [ -z "$ex" ] && { echo "  $lang: no exercises found"; continue; }
  vc="$(verify_for "$lang")"
  for mode in stub solution; do
    # The exercise directory must keep its own name. C++'s CMakeLists
    # derives the project and the test binary from it
    # (get_filename_component(exercise ${CMAKE_CURRENT_SOURCE_DIR} NAME)),
    # so a check running in "cpp-solution/" fails to configure and looks
    # identical to a reference solution that does not work.
    d="$WORK/_check/$lang-$mode/$ex"; rm -rf "$WORK/_check/$lang-$mode"
    mkdir -p "$(dirname "$d")"
    cp -R "$POLYGLOT/$lang/exercises/practice/$ex" "$d"
    prepare_dir "$lang" "$d"
    if [ "$mode" = solution ]; then install_reference "$lang" "$d" 2>/dev/null; fi
    rm -rf "$d"/.meta
    out="$( cd "$d" && eval "$(counting_command "$lang")" 2>&1 )"; rc=$?
    n="$(printf '%s\n' "$out" | count_tests "$lang")"
    printf '  %-11s %-16s %-8s exit=%d  tests_passed=%s\n' "$lang" "$ex" "$mode" "$rc" "$n"
    if [ "$mode" = solution ] && { [ "$rc" -ne 0 ] || [ "${n:-0}" -lt 2 ]; }; then
      echo "  !! $lang: the reference solution must pass, and run more than one test. Not trusting this harness." >&2
      exit 3
    fi
    if [ "$mode" = stub ] && [ "$rc" -eq 0 ]; then
      echo "  !! $lang: the untouched stub passes. Not trusting this harness." >&2
      exit 3
    fi
  done
done
echo
[ -n "${BENCH_CHECK_ONLY:-}" ] && { echo "(BENCH_CHECK_ONLY set; stopping after the harness check)"; exit 0; }

echo "== running =="
# One pool for every language, not one per language. With a pool per
# language the slowest exercise of each language blocked the start of the
# next: three workers idle for twelve minutes while one 408-bound retry
# finished, six times over.
#
# BENCH_ONLY=file re-runs just the "lang<TAB>exercise" pairs listed in
# it, appending to results.tsv — for re-measuring exercises whose first
# run ended in a provider error rather than a verdict.
pairs=""
if [ -n "${BENCH_ONLY:-}" ]; then
  pairs=$(awk -F'\t' 'NF>=2{print $1"\t"$2}' "$BENCH_ONLY")
else
  for lang in "$@"; do
    mkdir -p "$WORK/$lang"
    exercises=$(ls "$POLYGLOT/$lang/exercises/practice" 2>/dev/null)
    [ "$LIMIT" -gt 0 ] && exercises=$(printf '%s\n' "$exercises" | head -"$LIMIT")
    pairs="$pairs$(printf '%s\n' "$exercises" | sed "s/^/$lang\t/")
"
  done
fi
for lang in "$@"; do mkdir -p "$WORK/$lang"; done
printf '%s\n' "$pairs" | grep -v '^$' \
  | xargs -P "$JOBS" -L1 bash -c 'run_one "$0" "$1"'

echo
echo "== results =="
python3 - "$WORK/results.tsv" <<'PY'
import sys, collections
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
by = collections.defaultdict(lambda: [0, 0, 0.0])
for lang, _ex, res, _att, cost, _wall in rows:
    b = by[lang]
    b[0] += res == "PASS"
    b[1] += 1
    b[2] += float(cost or 0)
print(f"{'LANGUAGE':<12}{'SOLVED':>10}{'RATE':>8}{'COST':>11}")
print("-" * 41)
tp = tn = 0
tc = 0.0
for lang in sorted(by):
    p, n, c = by[lang]
    tp += p; tn += n; tc += c
    print(f"{lang:<12}{f'{p}/{n}':>10}{p / n * 100:>7.1f}%{c:>11.4f}")
print("-" * 41)
if tn:
    print(f"{'TOTAL':<12}{f'{tp}/{tn}':>10}{tp / tn * 100:>7.1f}%{tc:>11.4f}")
PY
echo "logs: $WORK/<lang>/<exercise>.log"
