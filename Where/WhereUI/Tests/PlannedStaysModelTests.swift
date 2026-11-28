import AccessibilitySnapshotParser
import SwiftUI
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct PlannedStaysModelTests {
    @Test func completedStaysAreRetainedInTheCollapsedPastSection() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let completed = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: -10),
            through: PlanningTestSupport.today.adding(days: -1),
        )
        let current = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today.adding(days: -3),
            through: PlanningTestSupport.today,
        )
        try await report.forecasts.create(stay: completed)
        try await report.forecasts.create(stay: current)
        let model = PlannedStaysModel(report: report, initialRegion: nil)
        await model.load()

        #expect(model.upcoming == [current])
        #expect(model.past == [completed])
        #expect(!model.showsPast)
        model.edit(completed)
        guard case let .edit(stay)? = model.editorRoute?.mode else {
            Issue.record("The planner must route to the selected completed stay")
            return
        }
        #expect(stay == completed)
        let firstID = try #require(model.editorRoute?.id)
        model.editorRoute = nil
        model.edit(completed)
        let reopened = try #require(model.editorRoute)
        #expect(reopened.id != firstID)
        guard case let .edit(reopenedStay) = reopened.mode else {
            Issue.record("Reopening must edit the same stay")
            return
        }
        #expect(reopenedStay.id == completed.id)
    }

    @Test func historicalGapChoiceClearsHomeWithoutDeletingPlans() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let stay = try PlanningTestSupport.stay(
            region: .newYork,
            from: PlanningTestSupport.today,
            through: PlanningTestSupport.today.adding(days: 7),
        )
        try await report.forecasts.create(stay: stay)
        try await report.forecasts.setHomeRegion(.california)
        let model = PlannedStaysModel(report: report, initialRegion: nil)
        await model.load()
        await model.usePastTravelPattern()

        let snapshot = try await report.services.plannedStays.snapshot()
        #expect(snapshot.homeRegion == nil)
        #expect(snapshot.stays == [stay])
    }

    @Test func addUsesTheShortcutRegionAndEachPresentationHasItsOwnIdentity() throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        let model = PlannedStaysModel(report: report, initialRegion: .newYork)
        model.add()
        let first = try #require(model.editorRoute)
        guard case let .new(initialRegion) = first.mode else {
            Issue.record("Add must route to a new stay")
            return
        }
        #expect(initialRegion == .newYork)
        model.editorRoute = nil
        model.add()
        let second = try #require(model.editorRoute)
        #expect(second.id != first.id)
    }

    @Test func failedGapChoiceRetainsTheOriginalErrorAndLoadedHome() async throws {
        let store = try TestStore()
        let report = PlanningTestSupport.report(store: store)
        try await report.forecasts.setHomeRegion(.california)
        let model = PlannedStaysModel(report: report, initialRegion: nil)
        await model.load()
        await store.failPlannedStays()

        await model.usePastTravelPattern()

        guard case let .failed(error) = model.saveState else {
            Issue.record("The failed Home change must stay visible in the planner")
            return
        }
        #expect(error is PlannedStaySaveFailure)
        #expect(!model.isSaving)
        #expect(report.forecasts.planning.homeRegion == .california)
        #expect(try await report.services.plannedStays.snapshot().homeRegion == .california)
    }

    @Test func returningToHomePickerStartsWithAFreshSearch() async throws {
        let report = try PlanningTestSupport.report(store: SwiftDataStore.inMemory())
        await report.forecasts.refresh()
        let root = PlannedStaysView(report: report).whereBroadwayRoot()
        let host: UIViewController = UIHostingController(rootView: root)

        try await show(host) { _ in
            try await openHomePicker(in: host.view)
            let field = try await searchField(in: host.view)
            field.text = "Nunavut"
            field.sendActions(for: .editingChanged)
            try await waitForAsync {
                HostedAccessibility.objects(in: host.view)
                    .contains { $0.accessibilityLabel == "Nunavut" }
            }

            let navigation = try #require(pushedNavigation(in: host))
            navigation.popViewController(animated: false)
            try await waitForAsync { navigation.viewControllers.count == 1 }
            try await openHomePicker(in: host.view)
            _ = try await searchField(in: host.view) { ($0.text ?? "").isEmpty }
        }
    }

    private func openHomePicker(in view: UIView) async throws {
        let home = String(localized: .plannedStaysHomeRegion)
        func link() -> NSObject? {
            HostedAccessibility.objects(in: view).first {
                $0.accessibilityLabel?.hasPrefix(home) == true
                    && $0.accessibilityTraits.contains(.button)
            }
        }
        try await waitForAsync { link() != nil }
        let row = try #require(link())
        if let control = row as? UIControl { control.sendActions(for: .touchUpInside) }
        else { try #require(row.accessibilityActivate()) }
    }

    private func searchField(
        in view: UIView,
        matching predicate: (UISearchTextField) -> Bool = { _ in true },
    ) async throws -> UISearchTextField {
        func field() -> UISearchTextField? {
            AdaptivePaneTestSupport.descendants(of: view, matching: UISearchTextField.self)
                .first { !$0.isHidden && $0.window != nil && predicate($0) }
        }
        try await waitForAsync { field() != nil }
        return try #require(field())
    }

    private func pushedNavigation(in controller: UIViewController) -> UINavigationController? {
        if let navigation = controller as? UINavigationController,
           navigation.viewControllers.count > 1
        {
            return navigation
        }
        return controller.children.lazy.compactMap { pushedNavigation(in: $0) }.first
    }
}
