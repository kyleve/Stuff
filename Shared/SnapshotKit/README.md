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
  navigation, tab, sheet, search, and toolbar chrome. A bounded
  or greedy production container that cannot converge must expose and
  snapshot its shared scrolling child directly, without snapshot-only layout
  behavior. The iPhone/iPad
  full-content presets retain their normal viewport height as a minimum and
  grow when content is taller. custom full-content frames shrink-wrap unless
  given a minimum. A frame also carries `safeAreaInsets` (default zero, keeping
  images device-independent). the `.iPhoneNotched` preset simulates real device
  chrome (Dynamic Island top 47pt, home-indicator bottom 34pt) for cases that
  must prove layout under it.
- **`SnapshotConfiguration.LayoutTraits`** — an explicit interface idiom and
  size-class set for adaptive content. The standard presets cover phone
  portrait, phone landscape, and tablet portrait. Each set adds a stable
  identifier token. If this value is `nil`, the capture inherits the host
  simulator traits.
- **`combinations(...)` + presets** — use `.componentRepresentative`,
  `.screenRepresentative`, or `.fullContentScreenRepresentative` for a representative
  layout. Use `.componentLightDark`, `.phoneLightDark`, or
  `.fullContentPhoneLightDark` for additional states of that layout.
  Focused `WithAX5`, `WithAnnotations`, and `WithAX5AndAnnotations` variants
  add separate light-mode captures for text wrapping and accessibility annotations;
  see the [preset declarations](Sources/SnapshotConfiguration+Combinations.swift).
- **Full-content frames** (`.iPhoneFullContent`, `.iPadFullContent`, and
  `.fullContent(name:width:)`) — capture the settled intrinsic height of
  scrolling content, including UIKit-backed SwiftUI `List` and `Form`
  containers, including when they are nested under production screen chrome.
  Device presets render at least one normal viewport tall, then expand to show
  content that would otherwise scroll. Fixed-height device frames are for
  non-scrolling subjects. Explicit `Frame.viewport` captures also cover bounded adaptive shells
  when paired with full-content captures of their scrolling panes.
- **Two-axis full-content frames** (`.iPhoneFullContent2D`,
  `.iPadFullContent2D`, and `.fullContent2D(name:minimumSize:)`) — start at a
  normal viewport and expand to one viewport-filling scroll view's complete
  width and height. Ordinary screen snapshots remain device-width. The capture
  pipeline bounds rendered pixel dimensions before allocation.
- **`SnapshotProviding`** — a type declares its variants via
  `static var snapshots: [SnapshotCase]`.
- **`SnapshotCase`** — a named group of configurations plus a lazy content
  builder. Declaring a matrix does not instantiate its views or models. The
  test runner evaluates the builder once per configuration. Models captured outside
  that builder and shared readiness hooks still need independent cases (see
  [`TODOs.md`](TODOs.md)). Cutsheet builders also run per configuration. Retries reuse the supplied view. SnapshotCase is
  also a `View`, so `snapshotPreviews` can render the whole matrix as a
  scrollable cutsheet inside a `#Preview`. Its `settle` axis
  (`SnapshotSettle`) declares whether the content needs the capture pipeline's
  async settle loop (`.settled`, the default) or is fully renderable after a
  layout pass (`.immediate` — skips the loop, so static content captures fast).
  `.settledAtLeast(minDuration:)` is `.settled` with a raised minimum window,
  for async appearance work that starts quiet and lands after the default floor
  (the native glass toolbar/tab bar material adaptation).
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
        SnapshotCase(name: "States", configurations: .componentRepresentative) {
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

- Representative component matrices contain five captures; representative screen
  matrices contain ten across phone and tablet. Light/dark presets contain two;
  focused presets add one AX5 capture, one standard-text annotation capture, or
  both (three or four total), without multiplying those axes.
  Keep each distinct state, but repeat the larger matrix only when its layout or
  accessibility structure warrants it. Add specific configurations for exceptional
  wrapping, contrast, or tablet behavior. Comparison sheets still render every panel.
- The former `*Defaults` presets are named `*Representative` to make that choice
  explicit. Their configurations, ordering, and reference identifiers are unchanged.
  The compact presets now belong to SnapshotKit and are available to every consumer.
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

## Component comparison sheets

Use `SnapshotCase.cutsheet` for one component state across consumer-defined
appearances. Each configuration produces a separate sheet. Panels retain normal
component width and wrap into two-column rows. The consumer supplies stable typed
identities, labels, ordering, and themed content:

```swift
SnapshotCase.cutsheet(
    name: "Badge",
    configurations: .componentRepresentative,
    referenceGroup: .themes,
) {
    for appearance in appearances {
        SnapshotPanel(id: appearance.snapshotID, label: appearance.title) {
            Badge(model: makeFreshFixture(), appearance: appearance)
        }
    }
}
```

Here, `Badge`, `appearances`, `snapshotID`, and the fixture factory are consumer-owned examples.
Build fresh fixture state inside each lazy panel builder. Preview sheets support
horizontal scrolling and omit test-only accessibility annotations.

Both case constructors accept an optional `SnapshotReferenceGroup`. Omission keeps
references ungrouped. The example explicitly selects `themes` for its theme panels. A group is a
stable lowercase slug, independent of localized labels and configuration identifiers.
Special traits use `other/` inside the group. See
[SnapshotKitTesting](../SnapshotKitTesting/README.md#component-comparison-sheets)
for capture, comparison, metadata, and recording behavior.

A case contains either one lazy view or a validated cutsheet. The ordinary initializer
cannot also accept panels, and the cutsheet factory cannot accept a second view tree.
Empty cutsheets and duplicate panel identities fail at declaration. Labels can repeat
when their identities differ. Raw capture content is available only through the
`Capture` SPI used by SnapshotKitTesting and Flyover. Previews use the same stored subject.

`SnapshotCase.ID` stores the reference group and case name separately. A slash in
an ungrouped case name cannot impersonate a grouped case in previews. Reference
filenames and configuration identifiers remain unchanged.

## Adaptive containers

Frame presets include explicit size classes and interface idiom. Component frames inherit these traits from their host.
Preview and capture hosts apply the same traits. Existing frame names and reference filenames stay unchanged.
Use `Frame.viewport` to capture bounded adaptive shells. Pair these images with full-content captures of each scrolling pane.
Create independent models and readiness hooks for each configuration. Keep one mounted model only in deliberate resize tests.
Device-specific profiles require measured runtime bounds, scale, insets, and reserved regions.
Synthetic windows test layout policy; they do not validate native folding or system bars.

The Duo presets use [native simulator measurements](Documentation/DuoMeasurements.json) from Xcode build `27A9275`, runtime `24A94232`.
All four profiles use 3× scale and the phone idiom.

| Frame | Bounds (points) | Horizontal / vertical size class | Insets (top, left, bottom, right) |
| --- | --- | --- | --- |
| `duoOuterPortrait` | 466 × 678 | compact / regular | 0, 0, 34, 84 |
| `duoOuterLandscape` | 678 × 466 | compact / compact | 0, 0, 34, 84 |
| `duoInnerPortrait` | 669 × 951 | regular / regular | 82, 0, 34, 0 |
| `duoInnerLandscape` | 951 × 669 | regular / regular | 0, 0, 34, 84 |

The inner display reports a 40-point division with 20-point margins on each adjoining side. Its frame already includes these margins.
The division is active when partially folded. Flat layouts must ignore inactive divisions.
The measurement record also contains camera and status-bar occlusions. Use current region geometry in production; these records describe specific simulator poses.

Explicit configuration layout traits override frame traits and retain their identifier tokens. With no explicit override, previews and captures use the frame’s measured traits.
