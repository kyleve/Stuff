# Log routing

The side-by-side Lean prototype in `Model.lean`
kernel-proves the current safety properties over every reachable state and
checks the broken trace. Run it with `./lean-check LogRouting`; TLC remains
checked in while repository-wide fairness/deadlock parity is open.

Models [`WhereScope.LogRouting`](../../WhereUI/Sources/Model/WhereScope.swift): only the
active scope registers on the process-global log sink; a late store for a
shadowed scope is remembered but not attached.

## Correspondence

| Model | Production |
| --- | --- |
| `activeScope` | `WhereModel` active real/demo/none |
| `realRouting` / `demoRouting` | per-scope `LogRouting` phase |
| `globalSinkOwner` | `Periscope.shared` registration |

## Properties

- `GlobalSinkSingleOwner`
- `ShadowedScopeNeverRoutes`
- `ActiveScopeRecordsReachSink`

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (attach on late open while shadowed) falsifies `ShadowedScopeNeverRoutes`.

Swift guard: [`DemoModeTests.aLogStoreOpeningLateNeverAttachesToAShadowedScope`](../../WhereUI/Tests/DemoModeTests.swift).

Note: static `WhereLog` bypass in Flyover remains tracked separately in [`Where/TODOs.md`](../../TODOs.md).

Run: `./tla-check LogRouting`
