# Test impact analysis

This standalone host tool exports source facts and compiler references for the
snapshot selection experiment. Read [README.md](README.md), [Tools rules](../AGENTS.md),
and the [repository rules](../../AGENTS.md).

- Keep dependencies in this package. Do not link the collector into application targets.
- SwiftSyntax supplies syntax facts only. Resolve identities through the compiler index.
- Emit repository-relative file paths. Reject stale indexes and unsupported syntax through explicit evidence fields.
- Do not interpret absence of an index edge as proof of independence. The Python planner owns conservative fallbacks.
- Run `swift test --package-path Tools/TestImpact --force-resolved-versions` after collector changes.
- Keep compiled fixture tests isolated from repository sources and simulators.
