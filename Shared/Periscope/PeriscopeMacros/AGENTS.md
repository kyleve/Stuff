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

- Require explicit string literals for scope and event IDs.
- Resolve field keys through the shared parser. Infer ASCII snake case only when the key is omitted.
- Reject invalid explicit keys and duplicate resolved keys. Require explicit keys for non-ASCII property names.
- Before renaming a property with an inferred key, preserve its previous key as an explicit literal.
- Generate classified method parameters from each `@LogField` declaration.
- Reject declarations that can create ambiguous generated code.
- Keep reserved event method names aligned with the instance API of `Log` and its public extensions.
- Keep restricted field values out of `classifiedFields`.
- Generate diagnostic projections through `LogExportField`. Apply requirements before encoding, and reject export overrides on shareable fields.

## Testing

Run `./test PeriscopeMacrosTests` for macro expansions and diagnostics.
Use Swift Testing and `SwiftSyntaxMacrosTestSupport`.
