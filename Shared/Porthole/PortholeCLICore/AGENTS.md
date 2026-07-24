# PortholeCLICore – Module Shape

PortholeCLICore is the logic behind the `porthole` CLI: the
`swift-argument-parser` command tree plus pure helpers for value parsing, output
formatting, and `--app` resolution. The `PortholeCLI` executable target is a
one-line `main.swift` over it. See [`README.md`](README.md) for the commands.

This file complements the root [`AGENTS.md`](../../../AGENTS.md) — read it first.

## Scope & dependencies

- Depends on **PortholeClientKit** (+ `ArgumentParser`). No device/runtime code.
- The `mcp` subcommand is a stub here; its real implementation and the
  `PortholeMCP` dependency are added in the MCP step.

## Invariants

- **Keep command logic thin and parsing/formatting pure.** `CLIValueParsing`,
  `OutputFormatting`, and `AppResolution` are free of I/O so they're unit-tested
  without a device; subcommands are glue that resolves an app, opens a
  `PortholeSession`, and prints. Add new testable logic as pure functions, not
  inside a `run()`.
- **Every session is closed** — `CLIRuntime.withSession` opens and always closes,
  even on throw.
- **Destructive actions confirm** unless `--yes`; `--param`/`--filter` infer
  scalar types with a string fallback, `--json` is the escape hatch.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PortholeCLICoreTests`, `extraPackageProducts: [PortholeClientKit, PortholeCore]`).
Cover parsing/formatting/resolution; the executable is built (not unit-tested) on
macOS via the `PortholeCLI` scheme.
