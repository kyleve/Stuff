# PeriscopeTools — Tool contracts

Read the [group contract](../AGENTS.md) and [repository contract](../../../AGENTS.md).
The [README](README.md) owns the API.

Consumers gate entry points behind `#if DEBUG`; developer strings are plain literals.
Keep app wiring in configuration and app imports out of the module.

## Design system — `PeriscopeStylesheet`

Use [building-ui](../../../.agents/skills/building-ui/SKILL.md).
Seed every public tool view through `periscopeBroadwayRoot()`, including inside a host Broadway root.
Consumers must not link Broadway products again; see the [target contract](../../../.agents/references/targets.md#never-double-link-a-product-whereui-already-carries).

Keep severity colors in `Palette`, with bands that also cover custom log levels.
Resolve row density through `RowStyle` and preserve the viewer's persisted preference.

## Invariants

- Choose NDJSON export mode explicitly. The viewer remains unfiltered unless product requirements change.
  Filtered export uses persisted permissions, excludes rendered messages/folded ambient snapshots, and never falls back to raw data after failure.
- Keep tools read-only over the store. Report every read/decode failure through `PeriscopeToolsLog.failures` in OSLog.
  Reporting through Periscope would trigger another reload and loop on corrupt rows.
- Combine indexed and decoded outcome values into one state; decode failure must not show an exit chip beside a running duration.
  Label names recovered from messages as recovered.
- Keep the toast handler overridable. Handlers must not log at or above the alerter threshold and trigger themselves.
- `Periscope.isInspectModeEnabled` owns inspect state; `PeriscopeInspector` mirrors it bidirectionally.
- Sort merged query results by `(date, sequence)`. Hierarchy/tree refreshes fetch only after the highest merged sequence and re-filter duplicates.
  Do not re-read the full store per commit. This intentionally does not reflect deletions; a store swap creates a fresh model.
  The remaining accumulated-state rebuild cost is tracked in the [backlog](https://linear.app/kve/view/c0511a6281eb).
- Key each view task by store identity and every identity-relevant input so in-place swaps rebind.
- Label the build scope pooled by timing readings; mixed optimization modes are not comparable.
  Filter accumulated span ends without refetching. Offer only resolvable scopes and fall back to `.all` when a selection stops resolving.

## Testing

Use hosted `PeriscopeToolsTests` in [Tests](Tests) with an in-memory store.
Drive models directly; host views with TestHostSupport.
