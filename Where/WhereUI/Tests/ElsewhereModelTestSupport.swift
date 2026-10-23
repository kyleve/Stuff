import Foundation
import RegionKit
import TestHostSupport
import WhereCore
@testable import WhereUI

actor HeldElsewhereResolver: ElsewhereResolving {
    private(set) var inputs: [ElsewhereInput] = []
    private var continuations: [Int: CheckedContinuation<ElsewhereReport, Error>] = [:]

    func resolve(_ input: ElsewhereInput) async throws -> ElsewhereReport {
        let index = inputs.count
        inputs.append(input)
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func complete(_ index: Int, with result: Result<ElsewhereReport, Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}

struct EmptyPlaceNamer: PlaceNaming {
    func name(for _: Coordinate) async -> String? {
        nil
    }
}

actor HeldPlaceNamer: PlaceNaming {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<String?, Never>?

    func name(for _: Coordinate) async -> String? {
        await withCheckedContinuation {
            isWaiting = true
            continuation = $0
        }
    }

    func complete(_ name: String) {
        continuation?.resume(returning: name)
        continuation = nil
    }
}

enum ElsewhereModelTestSupport {
    static func input(year: Int = 2026, region: Region = .other) -> ElsewhereInput {
        let day = DayPresence(day: CalendarDay(year: year, month: 6, day: 1), regions: [region])
        return ElsewhereInput(
            report: YearReport(year: year, days: [day], totals: [region: 1]),
            primaryRegions: [.california, .newYork],
            history: LocationHistoryProjection(samples: [], revisions: []),
            manualDays: [day],
            calendar: Calendar(identifier: .gregorian),
        )
    }

    static func result(_ input: ElsewhereInput, region: Region) -> ElsewhereReport {
        ElsewhereReport(year: input.report.year, regions: [ElsewhereRegion(
            region: region,
            days: input.report.days,
            locations: [],
            representativeCoordinate: nil,
        )])
    }

    static func waitForRequests(_ count: Int, in resolver: HeldElsewhereResolver) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await resolver.inputs.count < count {
            guard ContinuousClock.now < deadline
            else { throw TestHostError("Elsewhere did not request its projection") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
