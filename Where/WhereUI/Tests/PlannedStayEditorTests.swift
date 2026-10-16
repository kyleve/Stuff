import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct PlannedStayEditorTests {
    @Test(arguments: [false, true])
    func resizingDuringSavePreservesOneWriteAndItsResult(fails: Bool) async throws {
        let store = try TestStore()
        let report = PlanningTestSupport.report(store: store)
        await report.refresh()
        let model = PlannedStayEditorModel(report: report, mode: .new(initialRegion: .california))
        let state = AdaptiveHistoryHostState()
        let host = UIHostingController(rootView: AdaptiveHistoryHostedSurface(state: state) {
            PlannedStayEditor(model: model)
        })
        host.safeAreaRegions = []
        let gate = TestStore.PlanningOperationGate()
        await store.gateNextPlannedStayWrite(with: gate)
        if fails { await store.failPlannedStays() }
        try await show(host) { controller in
            let saving = Task { await model.save() }
            await gate.waitUntilReached()
            do {
                for pose in [
                    AdaptiveHistoryPose.outerPortrait,
                    .innerPortrait,
                    .tabletop,
                    .outerPortrait,
                ] {
                    try await AdaptiveHistoryTestSupport.resize(controller, state: state, to: pose)
                    #expect(model.isSaving)
                    #expect(model.region == .california)
                    #expect(await store.plannedStayWriteCount == 1)
                }
                #expect(await model.save() == false)
                #expect(await store.plannedStayWriteCount == 1)
                await gate.release()
                #expect(await saving.value == !fails)
                #expect(!model.isSaving)
                if fails {
                    guard case let .failed(error) = model.saveState else {
                        Issue.record("The failed save must remain visible after resizing")
                        return
                    }
                    #expect(error is PlannedStaySaveFailure)
                }
                let snapshot = try await report.services.plannedStays.snapshot()
                #expect(snapshot.stays.count == (fails ? 0 : 1))
            } catch {
                await gate.release()
                _ = await saving.value
                throw error
            }
        }
    }
}
