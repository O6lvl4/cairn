# Reproducible checks

Run `bash ci/check.sh` from a checkout with Almide installed, or set
`ALMIDE_BIN` to an absolute compiler path. This runs the existing tests, builds
`cairn`, and checks the built CLI against temporary fixtures. No model API or
credentials are used.

CI pins Almide to `dff9a458f2e581631bb6537c856a7974036e4153` and Rust to
`1.94.0`. Upgrade these deliberately and rerun the checks together. The compiler
binary cache is keyed by both versions. Smoke fixtures are regression coverage,
not a competitive benchmark or proof of general language correctness.
