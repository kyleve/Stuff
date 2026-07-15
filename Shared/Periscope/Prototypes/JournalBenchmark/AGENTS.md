# JournalBenchmark – Module Shape

A standalone macOS benchmark prototype (see [`README.md`](README.md))
comparing journal implementations for Periscope's crash-durability design —
it is **not** wired into the root `Package.swift`, any Tuist target, or CI,
and never ships. Build and run it directly with SwiftPM (`swift build -c
release`). Results and caveats live in the README; keep them updated if the
harness changes. Repo-wide rules live in the root
[`AGENTS.md`](../../../../AGENTS.md).
