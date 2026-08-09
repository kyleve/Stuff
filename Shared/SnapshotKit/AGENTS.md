# SnapshotKit – Module Shape

The generic, shippable half of the snapshot-testing framework: the appearance
*matrix* (`SnapshotConfiguration` + presets + `combinations` + identifiers), the
`SnapshotProviding` protocol, the `SnapshotCase` descriptor, and the
`snapshotPreviews` cutsheet. It drives both SwiftUI previews and the image
snapshot tests from one source of truth. See [`README.md`](README.md).

Complements the root [`AGENTS.md`](../../AGENTS.md) — read that first.

## Scope & dependencies

- **SwiftUI + Foundation + UIKit only. No snapshot-comparison engine.** This is
  load-bearing: UI modules link SnapshotKit (including in release) to drive
  previews, so it must never pull in `SnapshotTesting`/XCTest. The capture +
  comparison pipeline lives in [`SnapshotKitTesting`](../SnapshotKitTesting).
- Library target in [`Package.swift`](../../Package.swift); consumed by UI
  modules (currently `WhereUI`) for previews and by `SnapshotKitTesting` for the
  config→traits mapping. Tested by `SnapshotKitTests` (pure logic).

## Invariants an agent can't re-derive

- **`identifierParts` omit default axes.** Only non-default trait/frame/type
  values appear in a config's `identifier` (so `dark`, `xxxl`, `contrast`,
  `rtl`, `bold`, `accessibility`, `iPad` show up, but the
  light/standard/default baseline stays empty). Reference-image filenames
  depend on this, so changing the omission rules renames every snapshot —
  treat it as a wire format. Adding an axis is safe only with a default that
  is omitted (how `layoutDirection`/`legibilityWeight` landed).
- **`.accessibility` configs are preview-filtered.** `snapshotPreviews` drops
  them because VoiceOver annotations require the test-only library; they only
  render as snapshot tests. Don't "fix" previews to include them.
- **`SnapshotCase` content builders stay lazy.** Constructing a provider's
  descriptor array must not instantiate every view or model; each content
  access creates the independent value rendered by that configuration.
- **`\.isCapturingSnapshot` is for motion end-states only.** A view may read
  it only to freeze motion at a deterministic phase — never to change layout,
  content, or behavior. The one carve-out (documented on the property):
  content no settle window can make deterministic — externally-loaded
  substrates, wall-clock-dependent system controls, wall-clock timers — may
  substitute a placeholder of identical layout. It is a **hybrid** accessor
  (pure-SwiftUI `EnvironmentKey` first, `UITraitBridgedEnvironmentKey`
  fallback; the setter mirrors into both) — mechanics and why on
  `SnapshotCaptureFlag.swift`; don't simplify it to a plain `@Entry`.
- **Design-system-agnostic.** SnapshotKit never imports Broadway/WhereUI; the
  Broadway root wrap is a consumer concern (`WhereUI`'s `whereSnapshot(...)`).
- **Scrollable subjects use full-content frames.** A snapshot containing a
  `ScrollView`, `List`, `Form`, or equivalent UIKit-backed scroller uses
  `.fullContentScreenDefaults`, a consumer's matching compact preset, or an
  explicit `.fullContent` frame. Device full-content presets keep their normal
  viewport height as a minimum and grow only when the settled content is taller;
  custom full-content frames shrink-wrap unless given a minimum. Capture the
  production screen including its navigation, tab, sheet, search, and toolbar
  chrome when measurement converges. An intentionally bounded or greedy
  container instead snapshots its shared scrolling child directly; never add
  snapshot-only production layout. Fixed device frames are for non-scrolling
  subjects.

## Testing

`SnapshotKitTests` covers the matrix logic — `combinations` counts and
`identifierParts` omission — as pure value assertions (no rendering). The
rendering pipeline is exercised by consumers' snapshot bundles via
`SnapshotKitTesting`.
