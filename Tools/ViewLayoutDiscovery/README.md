# ViewLayoutDiscovery

A host executable using the repository's pinned SwiftSyntax and SwiftParser.
It accepts Swift source paths and emits one JSON dictionary keyed by path.
Each declaration records its qualified name, source line, inherited types,
generic context, kind, and conditional-compilation expression.

The [layout audit](../ViewLayoutAudit/README.md) resolves local inheritance,
selects view candidates, checks explicit registrations, and generates compiler
probes. Syntax discovery never estimates a type's memory layout.

```sh
swift build --product ViewLayoutDiscoveryTests
xcrun xctest .build/debug/ViewLayoutDiscoveryTests.xctest
```
