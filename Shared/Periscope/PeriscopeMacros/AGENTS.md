# PeriscopeMacros – Module Shape

PeriscopeMacros implements the classified logging macros.
See [`README.md`](README.md) for the public behavior.
Read the root [`AGENTS.md`](../../../AGENTS.md) and the Periscope [`AGENTS.md`](../AGENTS.md) first.

## Scope and dependencies

- Import only the SwiftSyntax products that `Package.swift` lists.
- Do not import `PeriscopeCore`.
- Generate references to public `PeriscopeCore` types as source text.
- Keep diagnostics deterministic and attached to the smallest relevant syntax node.

## Invariants

- Accept stable identifiers only as plain literals.
- Generate wire names from explicit identifiers, never Swift type names.
- Generate classified method parameters from each `@LogField` declaration.
- Reject declarations that can create ambiguous generated code.
- Keep restricted field values out of `classifiedFields`.

## Testing

Run `./test PeriscopeMacrosTests` for macro expansions and diagnostics.
Use Swift Testing and `SwiftSyntaxMacrosTestSupport`.
