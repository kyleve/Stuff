# JournalBenchmark – Module Shape

JournalBenchmark is a standalone macOS benchmark prototype. See [`README.md`](README.md). It compares journal implementations for Periscope's crash-durability design.

It is **not** wired into the root `Package.swift`, any Tuist target, or CI. It never ships.

Build and run it directly with SwiftPM (`swift build -c release`).

Results and caveats live in the README. If the harness changes, update them.

Repo-wide rules live in the root [`AGENTS.md`](../../../../AGENTS.md).
