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
