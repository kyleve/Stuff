import Foundation
import SnapshotKit
@_spi(Testing) import WhereCore
@testable import WhereUI

/// Drives the real report through controlled store reads. No presentation state is injected.
@MainActor
final class AdaptiveHistoryLoadFixture {
    enum State: String, CaseIterable {
        case loading
        case empty
        case failed
    }

    let report: YearReportModel
    private let store: TestStore
    private let refresh: Task<Void, Never>

    init(state: State) async throws {
        let store = try TestStore()
        self.store = store
        switch state {
            case .loading: await store.enableFirstSamplesGate()
            case .empty: break
            case .failed: await store.failSamples()
        }
        let now = PreviewSupport.referenceNow
        let report = YearReportModel(
            services: WhereServices(
                store: store,
                locationSource: ScriptedLocationSource(),
                now: { now },
            ),
            selectedYear: PreviewSupport.year,
            preferences: PreviewSupport.previewPreferences(),
            now: { now },
        )
        self.report = report
        refresh = Task { await report.refresh() }
        switch state {
            case .loading: await store.awaitFirstSamplesCall()
            case .empty, .failed: await refresh.value
        }
    }

    func finish() async {
        await store.releaseFirstSamplesCall()
        await refresh.value
    }
}
