# Measuring cairn, gramide and hew together

The objective is better repairs per unit of time and money. Faster parsing and
smaller reads matter only if they preserve the information needed to make a
correct edit. None of the results below establishes a world ranking.

## First checkpoint: correctness and repeatability (2026-09-10)

All three repositories now have a pinned-compiler CI command (`bash ci/check.sh`).
Local validation covered cairn's 7 test files, gramide's 9 and hew's 4, plus builds
and CLI smoke checks. These are file counts, not individual assertion counts.

Hew's comment/literal range regression made a six-line Rust function end at line
2 and invented a function inside its comment. The fix masks lexical contents
before declaration/range detection. Rust nested comments, raw delimiters and
lifetime-versus-character handling were checked against rustc_lexer at
`0d31508599a7814a7044e9a7a871e3dc5f037753`. Hew remains a heuristic reader, not a
full parser. The separate hew-lang compiler is not this project's hew tool.

Cairn's Almide benchmark previously passed unsupported `--agent`/`--steps`
options: those did not select another implementation. The harness now rejects
those legacy settings and supports `BENCH_CHECK_ONLY=1` to validate its original
and stripped exercise without a model call. Historical mode comparisons must be
re-established with actually distinct implementations.

## Comparison protocol

| Component | Primary outcome | Cost and performance | Correctness control |
|---|---|---|---|
| cairn | Independently verified repairs / all selected tasks | API cost including failures, wall time, attempts | Original tests retained; reference solutions hidden; setup failures reported separately |
| gramide | False rejection and false acceptance against reference parsers | Whole-corpus time, bytes/s, peak RSS | Pin language edition and corpus commit; include malformed input and recovery output |
| hew | Symbol names and exact source ranges; required code retained in selected reads | Returned bytes, latency, peak RSS | Annotated cases plus independent parser ranges; report unsupported constructs |
| combined | Repairs with gramide + hew versus the same agent without each | Total cost/time at equal model and attempt budget | One tool removed at a time; fixed task set and repeated runs |

Before comparing numbers, record tool/compiler commits, model identifier, prompt,
limits, corpus hashes, machine, process-startup policy and warmup policy. Report
all selected tasks, not only successful runs. Development fixtures and held-out
cases must have separate results. Unknown training exposure stays unknown.

Next checkpoints are an independent symbol-range corpus for hew, positive and
negative syntax corpus automation for gramide, and an externally defined repair
benchmark for cairn under a fixed model/budget. Run the harness-only checks before
spending model budget. Existing self-reported exercise scores and historical
speed measurements are leads to reproduce, not substitutes for these comparisons.

## Structured reading checkpoint

gramide's `symbols` contract now provides
versioned declaration names, owners and physical line/UTF-8 byte ranges. Hew uses
it for Almide, Go and Rust and labels heuristic fallbacks. The independent Go AST
comparison covers 38 reference source files and 551 concrete functions/methods;
its script and input hashes live in gramide's `docs/symbols.md` evidence.

Cairn consumes `hew read-json` when available, with built-in reads as the fallback.
Unlike display output, this preserves source, line endings and long lines. The
initial 24,000-character read expands to at most 96,000 characters when incomplete.
Files still truncated are context only: the complete-file edit path rejects them.
This does not yet implement model-selected symbol requests or targeted patch edits
for files larger than that budget. No repair-success or world-ranking claim follows
from these integration tests; paid model evaluations were not run.

## Language reference, and three things that did not work (2026-09-10)

One task, repeated: a JSON path picker implemented against 30 pre-written tests
in a language the model has not seen, `almide test` as the verify command,
`cf:glm-5.3-flash`, six attempts. Every number below is from that one task, so
none of it is a repair-success rate. The variance is reported because it is
larger than most of the effects.

**The reference works.** Without one, the run spent six attempts and produced
six hand-rolled functions that unwrap a `Result` by hand, plus a loop counting
a list the standard library already measures. With the toolchain's own
`almide ide stdlib-snapshot` — 14 KB of signatures, no syntax, no
configuration — the same task solved in two attempts for $0.012206 and none of
those helpers appeared. Repeated three more times: 3/3 solved, zero hand-rolled
unwrappers in all three. Every observed failure across every run was a compile
error; not one was a wrong answer. The gap the reference closes is knowing what
the API returns, not knowing how the language is written.

**Run-to-run variance is the headline.** Three runs of one identical
configuration: 2, 3 and 4 attempts; 139 s, 174 s and 456 s; $0.0093, $0.0096
and $0.0224; cyclomatic 18, 40 and 18. A single run cannot separate a change
from noise here, and three earlier single-run comparisons in this project were
noise.

**Polish did not work: three attempts, three failures.** Asking, once the verify
command already passes, for the same behaviour written more simply produced a
two-byte diff on the first run and a version that failed the tests on the second
and third. The rollback is sound — the tree came back byte-identical each time —
so the pass ships behind `--polish` at a default of 0, and as `cairn polish` for
a project that is already green. The command exists mostly so the pass can be
measured at all; before it, polish could only happen inside a repair.

**Asking for structure up front did not work either, and was worse.** Adding
"a type that names the cases, over flags and re-scanning a string" and two
similar lines to the edit question moved the model to sum types and recursive
descent — the shape a stronger model reaches for unprompted. It could not then
keep `Option[T]` and `T` apart. Five runs under that instruction had written
nothing by their second attempt, while three control runs had already finished;
their requests were streaming 500-760 KB each, generating without converging on
an answer of about 5 KB. The instruction was removed. Explaining the rejected
diagnostic on the re-ask, added while testing this, did not rescue it and was
kept for its own sake.

Taken together: the harness closes gaps in what the model knows, and does not
close gaps in what it can do. Structural quality — cyclomatic 18-40 against 6
for a stronger model on the same task — did not move under either intervention.

**Instrumentation earned more than the features.** Hedged requests looked
plausible until they reported themselves: three hedges fired, three lost, so the
second request was paid for and discarded every time. A rolled-back polish
reported `SOLVED` until the outcome was carried out of the loop. Twenty-eight
per cent of attempts were spending a whole model call on a rejected edit, which
was only visible by counting across saved logs. None of these were features; all
three changed a decision.

### Hedging, measured (2026-09-10)

Three runs of the final configuration solved 3/3 at $0.0078, $0.0111 and
$0.0106, in 168 s, 146 s and 221 s. Their eight model calls took 25, 26, 29,
46, 47, 73, 117 and 168 seconds — a median near 46 s and a tail at 117-168 s.

At a 75-second threshold the hedge fired five times across every run recorded
and won once. The other four were duplicate requests paid for and discarded.
The threshold is now 120000, above the merely-slow and below the tail, so the
second request is spent where the first is genuinely not arriving. This is
tuned on eight calls of one task; it is a starting point, not a constant.

The win rate is only visible because the hedge reports it. Before that, two
earlier runs containing a 231-second and a 565-second attempt could not be
told apart from ones where the hedge had rescued them.
