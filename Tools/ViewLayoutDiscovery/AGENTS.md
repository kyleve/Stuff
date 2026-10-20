# ViewLayoutDiscovery

The host SwiftSyntax executable inventories nominal declarations, local protocol
inheritance inputs, type aliases, and conditional compilation for the compiled
view audit. See [README.md](README.md), [tool rules](../AGENTS.md), and the
[root contract](../../AGENTS.md).

- Use the root package's pinned SwiftParser/SwiftSyntax dependencies.
- Emit syntax facts only; layout and conformance validity belong to the compiler.
- Preserve conditional branches and generic context. Reject malformed source.
- Keep discovery tests in `Tests/DiscoveryTests.swift`. Build the synthesized
  `ViewLayoutDiscoveryTests` product and run it with `xcrun xctest`.
