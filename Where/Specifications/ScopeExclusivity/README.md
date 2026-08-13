# Scope exclusivity

Models at-most-one active [`WhereScope`](../../WhereUI/Sources/Model/WhereScope.swift)
and at-most-one live real [`SwiftDataStore`](../../WhereCore/Sources/Store/SwiftDataStore.swift)
container over the user's store file. Complements
[`LogRouting`](../LogRouting/README.md), which covers Periscope sink ownership.
this spec covers scope/container *lifetime*.

## Correspondence

| Model | Production |
| --- | --- |
| `activeScope` | `WhereModel.activeScope` (real / demo / none) |
| `realContainersAlive` | live disk `ModelContainer` count (0 or 1 in production) |
| `demoContainerOpen` | in-memory demo / Flyover sibling container |
| `onboardingGate` | launch parks before `resolveScope()` until user chooses |
| `flyoverBuilt` | `WhereFlyoverWorld.build()` sibling scope (DEBUG) |

## Properties

- `AtMostOneActiveScope` — singleton active scope
- `GateBeforeOpen` — onboarding gate blocks real store open
- `NoOverlappingRealContainers` — at most one live real container at a time
- `RealReleasedBeforeRelogin` — logged-out state has no live real container

`BuildFlyoverSibling` leaves `activeScope` unchanged (Flyover never calls
`WhereModel.activateDemo`).

## Result

**Verified for these model bounds and assumptions** on `Current.cfg`.
`Broken.cfg` (second `ResolveRealScope` without releasing the first container)
falsifies `NoOverlappingRealContainers`.

Swift guards:

- [`WhereResetTests.loggingOutReleasesTheScopeBeforeTheNextLoginOpensOne`](../../WhereUI/Tests/WhereResetTests.swift)
- [`WhereLaunchTests.firstRunForegroundLaunchParksOnTheOnboardingGateBeforeOpeningAnything`](../../WhereUI/Tests/WhereLaunchTests.swift)
- [`WhereFlyoverWorldTests.buildsASeededSiblingWithoutActivatingIt`](../../WhereUI/Tests/WhereFlyoverWorldTests.swift)
- [`DemoModeTests.demoingFromAFreshInstallOpensNoRealStore`](../../WhereUI/Tests/DemoModeTests.swift)

Log sink routing is separately verified by [`LogRouting`](../LogRouting/README.md).
Static `WhereLog` bypass in Flyover remains in [`Where/TODOs.md`](../../TODOs.md).

Run: `./tla-check ScopeExclusivity`
