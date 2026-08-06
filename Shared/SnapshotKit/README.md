# SnapshotKit

SnapshotKit is the generic, shippable half of a small snapshot-testing
framework. It owns the *appearance matrix* that drives both SwiftUI previews and
image snapshot tests, so what you see in an Xcode Preview is exactly what CI
asserts against.

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
  Frames come in three sizing strategies: fixed device viewports (`.iPhone`,
  `.iPad`), the intrinsic `.component` frame, and `.fullContent(name:width:)` —
  fixed width, height measured from the settled content, so the whole
  scrollable content renders in one image with nothing scrolling. Full-width
  scrolling descendants drive the measured height while preserving surrounding
  navigation, tab, sheet, search, and toolbar chrome. The iPhone/iPad
  full-content presets retain their normal viewport height as a minimum and
  grow when content is taller; custom full-content frames shrink-wrap unless
  given a minimum. A frame also carries `safeAreaInsets` (default zero, keeping
  images device-independent); the `.iPhoneNotched` preset simulates real device
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
  content that would otherwise scroll; fixed-height device frames are for
  non-scrolling subjects.
- **`SnapshotProviding`** — a type declares its variants via
  `static var snapshots: [SnapshotCase]`.
- **`SnapshotCase`** — a named group of configurations plus a lazy content
  builder; declaring a matrix does not instantiate its views or models. It is
  also a `View`, so `snapshotPreviews` can render the whole matrix as a
  scrollable cutsheet inside a `#Preview`. Its `settle` axis
  (`SnapshotSettle`) declares whether the content needs the capture pipeline's
  async settle loop (`.settled`, the default) or is fully renderable after a
  layout pass (`.immediate` — skips the loop, so static content captures fast).
  `.settledAtLeast(minDuration:)` is `.settled` with a raised minimum window,
  for async appearance work that starts quiet and lands after the default floor
  (the iOS 26 glass toolbar/tab bar material adaptation).
  An optional `onReadyToSnapshot` hook runs in the capture pipeline after the
  content has settled and just before the image is taken — the deterministic
  point to focus a field or trigger a presented state; its effects are settled
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
  don't opt in are still settled by the pipeline's pixel-stability loop; the
  flag exists for motion that never settles (`repeatForever`,
  `TimelineView(.animation)`). One carve-out: content no settle window can make
  deterministic — externally-loaded substrates (live map tiles, remote images)
  and system controls whose rendering depends on wall-clock state (the compact
  `DatePicker`'s value capsule formats relative to *today's* date) — may
  substitute a deterministic placeholder of identical layout; the view's own
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
  preview cutsheet** — VoiceOver-annotated captures need the test-only library
  and can't render in a plain Preview. They still run as snapshot tests.
- The Where app wraps content in its Broadway design-system root via a
  `whereSnapshot(...)` adapter in `WhereUI`; SnapshotKit itself stays
  design-system-agnostic.
