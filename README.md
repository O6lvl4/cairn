# agent

A coding agent written in [Almide](https://github.com/almide/almide): one static
binary, no runtime to install, and every part of it — the parser it gates writes
with, the reader it shows files through, the summariser it compresses failures with
— is a program in the same language.

```
agent solve "the clamp test fails for out-of-range values" --root ../project
agent observe --root ../project     what it can establish without asking a model
agent llm-test                      one call, to prove the credentials work
```

## What it does

It observes first, then acts. Nothing is decided until the thing it depends on has
been looked at, and the model is asked one small question at a time:

1. **Observe** — marker file, language, the command whose exit status defines
   success, the file list, a ranked repository map, and the failing test's real
   output. All of it looked up, none of it guessed.
2. **Select** — which files to read. A project small enough to read whole is read
   whole, with no model call at all.
3. **Edit** — the model returns complete files. Each one is written through a syntax
   gate that refuses anything that does not parse, one file per write, so a good
   edit lands even when a bad one beside it is refused.
4. **Verify** — run the command again. A failing test is information the cheap model
   gets to use; only *unusable output* buys more reasoning, and then a stronger
   model.

Between attempts it feeds back what it actually changed (a unified diff), what was
rejected and why, the compiler's own explanation of any diagnostic code it emitted,
and — when the same failure repeats — an instruction to replace the approach rather
than adjust it.

## Why Almide

famulus5, the TypeScript agent this is ported from, scored 84–85% on the Aider
polyglot benchmark with an open-weights model. It needed Node, tree-sitter's native
grammars for its syntax gate, and a separate install for each. This one is a single
binary that ships with:

- **[gramide](https://github.com/O6lvl4/gramide)** for the syntax gate and the
  repository map — an Almide parser, corpus-verified, no native library.
- **[peek](https://github.com/O6lvl4/peek)** for structure-aware reads, when installed.
- **[ctxgate](https://github.com/O6lvl4/ctxgate)** for verdict-first failure
  summaries, when installed.

Each is optional; a missing binary means the built-in path, never an error.

## What the write gate covers

No file lands on disk unless it still parses. In tier order: a checker you configure
(`AGENT_CHECK_<EXT>`), then the language's own syntax-only tool, then nothing — and
"nothing" is reported, never assumed.

| language | checked by |
|---|---|
| Almide, Go | gramide (or `almide check` / `gofmt -e` when it is absent) |
| Rust | `rustfmt --emit stdout` — it parses without resolving, so an unresolved `use crate::…` still passes |
| Python, Ruby, JavaScript, PHP, Lua, shell, JSON, TOML | the tool each ships |
| Java, C++, C, C#, Kotlin, Scala, Swift, TypeScript | `gramide balance` — brackets and literals only. Their compilers need the whole project to tell a syntax error from a missing symbol, and a gate that refuses a correct edit is worse than none; this one cannot refuse valid code, and catches the failure that actually happens (a generation that stopped halfway) |

## Status

Honest: this is a port, and it is not yet measured against what it was ported from.
The loop, the guards and the retry policy are the ones famulus5 measured; whether
they carry the same score here is an open question, and `bench/almide.sh` is where
that gets answered. The seeded-bug check passes (one attempt, five seconds, two
hundredths of a cent).

## Build

```
almide build          # → ./agent
almide test           # 7 modules
```

Credentials come from the environment or a `.env` beside the project:
`CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`.

## Layout

| file | what it holds |
|---|---|
| `src/llm.almd` | the Workers AI call: streamed always, cost from `neurons`, truncation is an error |
| `src/ask.almd` | schema-constrained questions, and the retry policy (a 408 retries *smaller*) |
| `src/observe.almd` | markers, file lists, command running, what counts as a broken harness |
| `src/explain.almd` | `almide explain` / `rustc --explain`, and which part of a failure to show |
| `src/gate.almd` | the write gate: no file lands unless it parses |
| `src/solve.almd` | the loop |
| `src/main.almd` | the CLI |

## License

MIT or Apache-2.0, at your option.
