import Foundation
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeEvidencePreviewModelTests {
    @Test func expiredReadinessWaitsForTheRealScopeFailureAndReusesItsModel() async throws {
        let model = PortholeEvidencePreviewModel(surface: .expired)
        async let measurement: Void = model.prepare()
        async let capture: Void = model.prepare()
        _ = await (measurement, capture)
        let fixture = try #require(model.fixture).get()
        guard case let .failed(message) = fixture.evidence.state
        else { Issue.record("Readiness returned before expired evidence resolved"); return }
        #expect(message == PortholeError.staleScope.localizedDescription)
        await fixture.evidence.loadIfNeeded()
        await model.prepare()
        let rehosted = try #require(model.fixture).get()
        #expect(rehosted.evidence === fixture.evidence)
        #expect(rehosted.controller === fixture.controller)
        #expect(rehosted.object == fixture.object)
        guard case let .failed(retained) = rehosted.evidence.state
        else { Issue.record("Rehosting restarted the evidence load"); return }
        #expect(retained == message)
        fixture.controller.dismiss()
    }

    @Test func cancelledHostDoesNotLeaveTheSharedFixtureLoading() async throws {
        let model = PortholeEvidencePreviewModel(surface: .expired)
        let cancelledHost = Task { await model.prepare() }
        cancelledHost.cancel()
        await cancelledHost.value
        await model.prepare()
        let fixture = try #require(model.fixture).get()
        guard case .failed = fixture.evidence.state
        else { Issue.record("Cancelled host left evidence loading"); return }
        fixture.controller.dismiss()
    }
}
