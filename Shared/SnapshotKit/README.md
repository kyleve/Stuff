# SnapshotKit

SnapshotKit is the generic, shippable half of a small snapshot-testing
framework. It owns the *appearance matrix* that drives both SwiftUI previews and
image snapshot tests, so previews and CI share configurations, traits, and
content.

It deliberately imports **only** SwiftUI / Foundation / UIKit — never the
snapshot-comparison engine — so any UI module can depend on it (including in
release builds) without dragging test-only machinery into a shipping app. The
capture + comparison pipeline lives in the sibling
[`SnapshotKitTesting`](../SnapshotKitTesting) module.

## What's in the box

- **`SnapshotConfiguration`** — one rendering variant: color scheme, Dynamic
  Type size, contrast, layout direction (`rtl` token), legibility weight (bold
  text, `bold` token), a device `Frame`, and a `snapshotType` (`.standard` or
  `.accessibility`). `Hashable`, with an `identifier` (built from
  `identifierParts`) that **omits default axes** so common cases stay terse.
  Frames come in four sizing strategies: fixed device viewports (`.iPhone`,
  `.iPad`), the intrinsic `.component` frame, `.fullContent(name:width:)`, and
  `.fullContent2D(name:minimumSize:)`. The ordinary full-content frame has a
  fixed width and a height measured from the settled content. Use the explicit
  two-axis frame for spatial canvases that scroll in both dimensions. Full-width
  scrolling descendants drive the measured height while preserving surrounding
  navigation, tab, sheet, search, and toolbar chrome. An bounded
  or greedy production container that cannot converge must expose and
  snapshot its shared scrolling child directly, without snapshot-only layout
  behavior. The iPhone/iPad
  full-content presets retain their normal viewport height as a minimum and
  grow when content is taller. custom full-content frames shrink-wrap unless
  given a minimum. A frame also carries `safeAreaInsets` (default zero, keeping
  images device-independent). the `.iPhoneNotched` preset simulates real device
  chrome (Dynamic Island top 47pt, home-indicator bottom 34pt) for cases that
  must prove layout under it.
- **`combinations(...)` + presets** (`.componentDefaults`, `.screenDefaults`,
  `.fullContentScreenDefaults`) — expand a terse declaration into the full
  matrix.
- **Full-content frames** (`.iPhoneFullContent`, `.iPadFullContent`, and
  `.fullContent(name:width:)`) — capture the settled intrinsic height of
  scrolling content, including UIKit-backed SwiftUI `List` and `Form`
  containers, including when they are nested under production screen chrome.
  Device presets render at least one normal viewport tall, then expand to show
  content that would otherwise scroll. fixed-height device frames are for
  non-scrolling subjects.
- **Two-axis full-content frames** (`.iPhoneFullContent2D`,
  `.iPadFullContent2D`, and `.fullContent2D(name:minimumSize:)`) — start at a
  normal viewport and expand to one viewport-filling scroll view's complete
  width and height. Ordinary screen snapshots remain device-width. The capture
  pipeline bounds rendered pixel dimensions before allocation.
- **`SnapshotProviding`** — a type declares its variants via
  `static var snapshots: [SnapshotCase]`.
- **`SnapshotCase`** — a named group of configurations plus a lazy content
  builder. declaring a matrix does not instantiate its views or models. It is
  also a `View`, so `snapshotPreviews` can render the whole matrix as a
  scrollable cutsheet inside a `#Preview`. Its `settle` axis
  (`SnapshotSettle`) declares whether the content needs the capture pipeline's
  async settle loop (`.settled`, the default) or is fully renderable after a
  layout pass (`.immediate` — skips the loop, so static content captures fast).
  `.settledAtLeast(minDuration:)` is `.settled` with a raised minimum window,
  for async appearance work that starts quiet and lands after the default floor
  (the iOS 26 glass toolbar/tab bar material adaptation).
  Intrinsic/full-content cases also have a `measurementReadiness` axis. Its
  default, `.sameAsCapture`, preserves the existing behavior for content whose
  loaded state changes its height. Deterministically sized fixtures may use
  `.immediate` to skip the sizing probe's settle while retaining the final
  capture's `.settled` or `.settledAtLeast` policy. `.settled` decouples ordinary
  sizing quiescence from a raised final-capture floor.
  When async content changes ideal height, `onReadyToMeasure` can instead await
  a deterministic completion signal after the intrinsic probe is hosted and
  laid out but before it settles and measures. The hook is invalid for fixed
  sizing and is bounded by the capture's effective settle ceiling.
  An optional `onReadyToSnapshot` hook runs in the capture pipeline after the
  content has settled and before the image is taken — the deterministic
  point to focus a field or trigger a presented state. its effects are settled
  again before capture. The preview cutsheet ignores the hook (only the test
  pipeline can re-settle around it).
- **`snapshotTraits(_:)`** — applies a configuration's traits to a view for the
  preview cutsheet (color scheme, Dynamic Type, layout direction, legibility
  weight, and an increased-contrast trait override), so previews and test
  captures stay in lockstep. Simulated frame insets are capture-only — a
  preview can't fake safe areas.
- **`\.isCapturingSnapshot`** — an environment flag that is `true` while
  `SnapshotKitTesting` captures the view (and in the preview cutsheet, which
  mirrors the tests). A view may read it **only** to render a deterministic
  end-state of motion — an animation's final frame, a canonical phase of a
  looping indicator — never to change layout, content, or behavior. Views that
  don't opt in are still settled by the pipeline's pixel-stability loop. the
  flag exists for motion that never settles (`repeatForever`,
  `TimelineView(.animation)`). One carve-out: content no settle window can make
  deterministic — externally-loaded substrates (live map tiles, remote images)
  and system controls whose rendering depends on wall-clock state (the compact
  `DatePicker`'s value capsule formats relative to *today's* date) — may
  substitute a deterministic placeholder of identical layout. the view's own
  chrome (markers, overlays, legends, row titles) still renders for real. The
  same rationale covers wall-clock timers that flip visible state (whether one
  has fired by capture time races the settle loop): under capture a view may
  skip the timer and let an explicit per-case seam pin each state (the Where
  launch splash's slow-launch caption). It is
  bridged from a UIKit trait (`SnapshotCaptureTrait`) so it crosses
  `UIHostingController` boundaries.

## Quick start

Conform a component and preview its matrix:

```swift
extension MyBadge: SnapshotProviding {
    static var snapshots: [SnapshotCase] {
        SnapshotCase(name: "States", configurations: .componentDefaults) {
            VStack {
                MyBadge(count: 1)
                MyBadge(count: 99)
            }
        }
    }
}

#if DEBUG
#Preview { MyBadge.snapshotPreviews }
#endif
```

Then assert them from a snapshot test bundle (see
[`SnapshotKitTesting`](../SnapshotKitTesting)):

```swift
assertSnapshots(of: MyBadge.self)
```

## Notes

- Accessibility (`.accessibility`) configurations are **filtered out of the
  preview cutsheet** — Stuff keeps AccessibilitySnapshot's SwiftUI annotation
  renderer in the test-only `SnapshotKitTesting` product instead of linking it
  into every shipping UI module. They still run as snapshot tests. The cutsheet
  also cannot reproduce the capture pipeline's UIKit-backed `List`/`Form`
  height measurement, safe-area override, readiness hooks, or
  tile-and-stitch pass, so CI's rendered dimensions remain authoritative.
- The Where app wraps content in its Broadway design-system root via a
  `whereSnapshot(...)` adapter in `WhereUI`. SnapshotKit itself stays
  design-system-agnostic.
