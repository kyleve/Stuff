# PeriscopeMacros

PeriscopeMacros generates classified event code for `PeriscopeCore`.
It validates stable scope, event, and field identifiers at compile time.
It also generates typed log methods that require classified inputs.

## Public macros

- `@LogScope` defines a namespace that conforms to `LogScopeDefinition`.
- `@LogEvent` defines a nested event that conforms to `LogEvent`.

Application modules import `PeriscopeCore` to use both macros.
They do not import this implementation module.

`@LogEvent` generates stable coding keys, classified initializers, safe field projections, and event metadata.
`@LogScope` generates the scope definition and compiler-checked event methods on `Log<Scope>`.

Generated parameters encode exposure, semantic kind, and Swift value type.
A call site uses inputs such as `.shared(.count, value)` or `.restricted(.identifier, value)`.

Repository code must use these macros. The runtime protocols keep safe defaults for external manual conformances, but repository sources and tests cannot conform directly.

Stable IDs are wire data. A macro accepts only plain string literals for scope, event, and field IDs. An incompatible event payload needs a positive new version.

## Development

The root `Package.swift` pins SwiftSyntax exactly.
Run the host tests with `./test PeriscopeMacrosTests`.
This command does not select an iOS simulator.

Macro expansion tests use SwiftSyntax test support and Swift Testing.
The compiler tests generated constraints when application targets compile.
