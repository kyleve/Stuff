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

Event method names must not collide with existing `Log` members, such as `info`, `record`, or `context`.
The macro diagnoses these names at the event declaration.

Repository code must use these macros. The runtime protocols keep safe defaults for external manual conformances, but repository sources and tests cannot conform directly.

Scope and event IDs are explicit string literals. Field keys can be explicit string literals or inferred from property names.
An incompatible event payload needs a positive new version.

```swift
@LogField(exposure: .shareable, kind: .count)
var sampleCount: Int // sample_count

@LogField("sample_count", exposure: .shareable, kind: .count)
var numberOfSamples: Int // preserves the key after a rename
```

Inference converts ASCII names to snake case at compile time.
It converts `sampleID` to `sample_id`, `URLLoadFailed` to `url_load_failed`, and `http2Status` to `http2_status`.
Existing underscores remain unchanged. Identifier backticks do not enter the key.
Non-ASCII property names require an explicit key.
An empty or nonliteral explicit key produces a diagnostic, not an inferred key.
Duplicate resolved keys produce a diagnostic, including collisions between explicit and inferred keys.

Inferred keys change with property names. They are not inherently rename-safe.
Before you rename a property, add its previous key as an explicit literal.
For an intentional incompatible key change, increase the event version.
Existing explicit keys remain unchanged.

Static messages and identifiers accept escaped, raw, and multiline string literals, but not interpolation.
The generated values preserve the literal's decoded text.

## Development

The root `Package.swift` pins SwiftSyntax exactly.
Run the host tests with `./test PeriscopeMacrosTests`.
This command does not select an iOS simulator.

Macro expansion tests use SwiftSyntax test support and Swift Testing.
The compiler tests generated constraints when application targets compile.
