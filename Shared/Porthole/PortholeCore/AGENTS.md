# PortholeCore

Shared debugger contracts; see [README.md](README.md) and the repository
[contract](../../../AGENTS.md).

- Import Foundation and CryptoKit. Use CryptoKit only to hash bundled source. Keep execution and credential storage in other modules.
- Keep wire values independent of SwiftUI and provider-specific tool formats.
- Preserve Int64 and UInt64 exactly. Reject unsupported integral numbers on both encoding and decoding; compare numeric representations without rounding.
- Use typed identities and generation-scoped object references.
- Keep typed observation clients on ordinary invocation; keep native owner identities out of tool arguments.
- Version persisted documents at their owning boundary; preserve wire case names.
- Keep planned coverage separate from installed support. Preserve inactive declarations, source-only exclusions, build identity, and source hashes in typed reports.
- Bind coverage pages to their scope generation and reject malformed page bounds before presenting evidence.
- Cover serialization and validation with Swift Testing in Tests.
