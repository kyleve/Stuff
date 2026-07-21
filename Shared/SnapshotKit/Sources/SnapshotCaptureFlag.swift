import SwiftUI
import UIKit

// The accessor must stay a manual environment key: it bridges a UIKit trait
// (`SnapshotCaptureTrait`), which `@Entry` can't express, so keep SwiftFormat
// from rewriting it.
// swiftformat:disable environmentEntry

/// The UIKit trait behind ``SwiftUICore/EnvironmentValues/isCapturingSnapshot``.
///
/// The capture pipeline in `SnapshotKitTesting` sets this on the captured view
/// controller via `traitOverrides`, and UIKit propagates it down the hosted
/// tree — so the flag reaches the SwiftUI content however it is hosted (plain,
/// accessibility-wrapped, or re-hosted for intrinsic measurement), and crosses
/// any `UIHostingController` boundary in between.
public struct SnapshotCaptureTrait: UITraitDefinition {
    public static let defaultValue = false
    public static let affectsColorAppearance = false
    public static let name = "Capturing Snapshot"
    public static let identifier = "com.stuff.snapshotkit.isCapturingSnapshot"
}

private struct IsCapturingSnapshotKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = false

    static func read(from traitCollection: UITraitCollection) -> Bool {
        traitCollection[SnapshotCaptureTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) {
        mutableTraits[SnapshotCaptureTrait.self] = value
    }
}

/// A pure-SwiftUI capture flag set by SwiftUI-native callers (the preview
/// cutsheet's `.environment(\.isCapturingSnapshot, true)`, or any `.environment`
/// override). Because it's an ordinary `EnvironmentKey` — not trait-bridged — it
/// propagates synchronously through the SwiftUI tree with no `UITraitCollection`
/// round-trip or first-frame lag. `nil` means "no SwiftUI ancestor set one", so
/// the accessor falls back to the UIKit-bridged value. This mirrors Broadway's
/// `BContext+SwiftUI` bridging, and is why the capture pipeline's
/// `traitOverrides`-set value (UIKit) still reaches SwiftUI via the fallback.
private struct SwiftUIIsCapturingSnapshotKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// `true` while `SnapshotKitTesting` captures this view for a snapshot test,
    /// and in the ``SnapshotProviding/snapshotPreviews`` cutsheet (previews
    /// mirror what the tests capture).
    ///
    /// **Contract:** a view may read this flag *only* to render a deterministic
    /// end-state of motion — an animation's final frame, a canonical phase of a
    /// looping indicator — never to change layout, content, or behavior. The
    /// pipeline's pixel-stability settle loop remains the fallback for views
    /// that don't opt in; the flag exists for motion that never settles
    /// (`repeatForever` animations, `TimelineView(.animation)`).
    ///
    /// **The one carve-out:** content whose rendering no settle window can
    /// make deterministic — externally-loaded substrates (live map tiles,
    /// remote images) and system controls whose rendering depends on
    /// wall-clock state (the compact `DatePicker` formats its value capsule
    /// relative to *today's* date) — may substitute a deterministic
    /// placeholder of *identical layout* (same frame, same chrome).
    /// Keep the placeholder honest: the view's own chrome (markers, overlays,
    /// legends, row titles) must still render for real; only the
    /// nondeterministic element is substituted (see the Where app's
    /// `RegionMapView` and `WhereDatePicker`).
    ///
    /// The same determinism rationale covers **wall-clock timers that flip
    /// visible state**: whether such a timer has fired by capture time races
    /// the settle loop's variable duration, so under capture a view may skip
    /// the timer entirely and let an explicit per-case seam pin the state —
    /// each state then gets its own snapshot case (see the Where app's launch
    /// splash, whose slow-launch caption shows iff its `previewShowsCaption`
    /// seam says so). Everything else must render real content.
    ///
    /// A SwiftUI-set value (the preview cutsheet, or any `.environment`
    /// override) is read synchronously from a pure-SwiftUI key; with none set,
    /// it falls back to the value bridged from the nearest UIKit ancestor's
    /// trait collection (how the test pipeline's `traitOverrides` reaches
    /// SwiftUI). Writing mirrors into both so a SwiftUI-set flag also reaches
    /// nested UIKit.
    public var isCapturingSnapshot: Bool {
        get { self[SwiftUIIsCapturingSnapshotKey.self] ?? self[IsCapturingSnapshotKey.self] }
        set {
            self[SwiftUIIsCapturingSnapshotKey.self] = newValue
            self[IsCapturingSnapshotKey.self] = newValue
        }
    }
}
