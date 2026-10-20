# Compiled layout audit

See [README.md](README.md), the [tooling rules](../AGENTS.md), and the
[root contract](../../AGENTS.md).

- Keep probes metatype-only. Never instantiate a view or evaluate `body`.
- Preserve audience conditions and optimization. Never enable audit targets in
  distribution archives. Fail missing, partial, or stale measurement reports.
- Treat generic cases as finite coverage. Require explicit reasons for gaps and
  baseline exceptions; CI must never raise budgets automatically.
- Keep generated hooks dependency-free beyond Foundation/SwiftUI and compile
  them only under `VIEW_LAYOUT_AUDIT`. Do not add production package links for
  measurement support.
