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

    /// Collects which segment the builder reported as selected.
    private final class Sink {
        var selected: [Seg] = []

        func record(_ segment: Seg, isActive: Bool) {
            if isActive { selected.append(segment) }
        }
    }

    @Test func restoresPersistedSelectionAcrossLaunches() throws {
        let key = SegmentStoreKey.year
        // Simulate a prior launch having selected `.third`.
        UserDefaults.standard.set(Seg.third.rawValue, forKey: key.rawValue)
        defer { UserDefaults.standard.removeObject(forKey: key.rawValue) }

        let sink = Sink()
        // All segments are built (they stay mounted), so key off the `isActive`
        // flag to learn which one is selected rather than which one was built.
        let view = SegmentedTabContainer(
            storageKey: key,
            initialSelection: Seg.first,
            pickerLabel: "Test",
        ) { segment, isActive in
            let _ = sink.record(segment, isActive: isActive)
            Color.clear
        }

        try show(UIHostingController(rootView: view)) { hosted in
            #expect(hosted.view != nil)
        }

        // The persisted `.third` is the active segment, not the `.first` initial.
        #expect(sink.selected.contains(.third))
        #expect(!sink.selected.contains(.first))
    }
}
