import Foundation
import WhereCore
@testable import WhereUI

/// Holds the actual export-read boundary so cancellation and retirement can race its result.
actor HeldHistoryReportSource: HistoryReportExporting {
    let report: HistoryReportCSV
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var held: CheckedContinuation<Void, Never>?

    init(report: HistoryReportCSV) {
        self.report = report
    }

    func exportableYearCSV(for _: Int) async throws -> HistoryReportCSV {
        guard !entered else { return report }
        await withCheckedContinuation {
            held = $0
            entered = true
            entryWaiters.forEach { $0.resume() }
            entryWaiters.removeAll()
        }
        return report
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        held?.resume(); held = nil
    }
}

struct FailedHistoryReportSource: HistoryReportExporting {
    enum Failure: Error { case unavailable }
    func exportableYearCSV(for _: Int) async throws -> HistoryReportCSV {
        throw Failure.unavailable
    }
}

@MainActor
enum HistoryReportExportTestSupport {
    static func completeFixture() async throws -> RecordingReviewTestSupport.Fixture {
        try await RecordingReviewTestSupport.fixture(samples: [
            RecordingReviewTestSupport.sample(
                deviceID: RecordingReviewTestSupport.first,
                seconds: 0,
            ),
        ])
    }

    static func model(
        _ fixture: RecordingReviewTestSupport.Fixture,
        year: Int,
    ) -> HistoryReportExportModel {
        HistoryReportExportModel(
            source: fixture.services.reports,
            validate: fixture.services.validateDataAccess,
            year: year,
            isAvailable: true,
        )
    }
}
