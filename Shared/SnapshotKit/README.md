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
  Type size, contrast, a device `Frame`, and a `snapshotType` (`.standard` or
  `.accessibility`). `Hashable`, with an `identifier` (built from
  `identifierParts`) that **omits default axes** so common cases stay terse.
- **`combinations(...)` + presets** (`.componentDefaults`, `.screenDefaults`) —
  expand a terse declaration into the full matrix.
- **`SnapshotProviding`** — a type declares its variants via
  `static var snapshots: [SnapshotCase]`.
- **`SnapshotCase`** — a named group of configurations plus the content to
  render; it is also a `View`, so `snapshotPreviews` can render the whole matrix
  as a scrollable cutsheet inside a `#Preview`.
- **`snapshotTraits(_:)`** — applies a configuration's traits to a view for the
  preview cutsheet (color scheme, Dynamic Type, and an increased-contrast trait
  override).
- **`\.isCapturingSnapshot`** — an environment flag that is `true` while
  `SnapshotKitTesting` captures the view (and in the preview cutsheet, which
  mirrors the tests). A view may read it **only** to render a deterministic
  end-state of motion — an animation's final frame, a canonical phase of a
  looping indicator — never to change layout, content, or behavior. Views that
  don't opt in are still settled by the pipeline's pixel-stability loop; the
  flag exists for motion that never settles (`repeatForever`,
  `TimelineView(.animation)`). It is bridged from a UIKit trait
  (`SnapshotCaptureTrait`) so it crosses `UIHostingController` boundaries.

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
