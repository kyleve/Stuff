# Periscope – Module Group Shape

Periscope owns observability. See [README.md](README.md), the [root contract](../../AGENTS.md), and each module's instructions.

## Modules & dependencies

UI depends on Core; Tools depends on both. Only Tools may depend on Broadway; Core and UI stay design-system-free.
Macros run on the build host. JournalKit stays payload-agnostic.
`Prototypes/JournalBenchmark` belongs to no target or CI job.

## Invariants an agent can't re-derive

- Consumers declare root facades with `@LogScope`, `@LogEvent`, and `@LogField`; use generated classified emission methods, not direct event conformances.
- All roots record into one process-wide `Periscope.shared`. The host app attaches the store once; library code never attaches one. Non-persisting extension processes stay OSLog-only.
- The host supplies `LogSession.attributes`. Periscope cannot read build stamps or invent values; unstamped bundles supply an empty dictionary.
- Tests use a fresh system and in-memory store. Pass `system:` explicitly: `Log<Scope>()` defaults to `.shared`, a deliberate exception to the no-Core-defaults convention.

## Testing

Hosted Swift Testing bundles (`PeriscopeCoreTests`, `PeriscopeUITests`, `PeriscopeToolsTests`) run in `StuffTestHost`.
