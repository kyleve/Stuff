# SnapshotKit – Module Shape

SnapshotKit is the generic, shippable half of the snapshot-testing framework. It provides the appearance *matrix* (`SnapshotConfiguration` + presets + `combinations` + identifiers), the `SnapshotProviding` protocol, the `SnapshotCase` descriptor, and the `snapshotPreviews` cutsheet. It drives both SwiftUI previews and image snapshot tests from one source of truth. See [`README.md`](README.md).

Read the root [`AGENTS.md`](../../AGENTS.md) first.

## Scope & dependencies

- **Use SwiftUI, Foundation, and UIKit only. Do not link a snapshot-comparison engine.** UI modules link SnapshotKit (including in release) to drive previews. It must never pull in `SnapshotTesting`/XCTest. The capture and comparison pipeline lives in [`SnapshotKitTesting`](../SnapshotKitTesting).
- **Declare the library target in [`Package.swift`](../../Package.swift).** UI modules (currently `WhereUI`) consume it for previews. `SnapshotKitTesting` consumes it for the config→traits mapping. `SnapshotKitTests` covers pure logic.

## Invariants an agent can't re-derive

- **`identifierParts` omit default axes.** Only non-default trait, frame, and type values appear in a config's `identifier` (so `dark`, `xxxl`, `contrast`, `rtl`, `bold`, `accessibility`, `iPad` show up, but the light/standard/default baseline stays empty). Reference-image filenames depend on this. Treat omission rules as a wire format. When you add an axis, give it a default that is omitted (how `layoutDirection`/`legibilityWeight` landed).
- **Filter `.accessibility` configs out of previews.** `snapshotPreviews` drops them because VoiceOver annotations require the test-only library. They render only as snapshot tests. Do not "fix" previews to include them.
- **Keep `SnapshotCase` content builders lazy.** Constructing a provider's descriptor array must not instantiate every view or model. Each content access creates the independent value rendered by that configuration.
- **Use `\.isCapturingSnapshot` for motion end-states only.** A view may read it only to freeze motion at a deterministic phase. Never use it to change layout, content, or behavior. One carve-out (documented on the property): content no settle window can make deterministic — externally-loaded substrates, wall-clock-dependent system controls, wall-clock timers — may substitute a placeholder of identical layout. It is a **hybrid** accessor (pure-SwiftUI `EnvironmentKey` first, `UITraitBridgedEnvironmentKey` fallback. The setter mirrors into both). See mechanics and rationale on `SnapshotCaptureFlag.swift`. Do not simplify it to a plain `@Entry`.
- **Keep SnapshotKit design-system-agnostic.** SnapshotKit never imports Broadway/WhereUI. The Broadway root wrap is a consumer concern (`WhereUI`'s `whereSnapshot(...)`).
- **Use full-content frames for scrollable subjects.** If a snapshot contains a `ScrollView`, `List`, `Form`, or equivalent UIKit-backed scroller, use `.fullContentScreenDefaults`, a consumer's matching compact preset, or an explicit `.fullContent` frame. Device full-content presets keep their normal viewport height as a minimum. They grow only when the settled content is taller. Custom full-content frames shrink-wrap unless given a minimum. Capture the production screen including navigation, tab, sheet, search, and toolbar chrome when measurement converges. If a container is intentionally bounded or greedy, snapshot its shared scrolling child directly. Never add snapshot-only production layout. Fixed device frames are for non-scrolling subjects.

## Testing

`SnapshotKitTests` covers the matrix logic — `combinations` counts and `identifierParts` omission — as pure value assertions (no rendering). Consumers' snapshot bundles exercise the rendering pipeline through `SnapshotKitTesting`.
