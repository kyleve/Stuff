import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

/// Confirms ``SegmentedTabContainer`` restores the segment persisted under its
/// ``SegmentStoreKey`` rather than always opening on the initial one.
@MainActor
struct SegmentedTabContainerTests {
    private enum Seg: String, CaseIterable, SegmentedItem {
        case first
        case second
        case third

        var title: String {
            rawValue
        }
    }

    /// Collects which segment the content builder was asked to render.
    private final class Sink {
        var segments: [Seg] = []
    }

    @Test func restoresPersistedSelectionAcrossLaunches() throws {
        let key = SegmentStoreKey.year
        // Simulate a prior launch having selected `.third`.
        UserDefaults.standard.set(Seg.third.rawValue, forKey: key.rawValue)
        defer { UserDefaults.standard.removeObject(forKey: key.rawValue) }

        let sink = Sink()
        let view = SegmentedTabContainer(
            storageKey: key,
            initialSelection: Seg.first,
            pickerLabel: "Test",
        ) { segment in
            // Record the rendered segment; the builder runs only for the
            // selected one.
            let _ = sink.segments.append(segment)
            Color.clear
        }

        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }

        // The persisted `.third` is shown, not the `.first` initial value.
        #expect(sink.segments.contains(.third))
        #expect(!sink.segments.contains(.first))
    }
}
