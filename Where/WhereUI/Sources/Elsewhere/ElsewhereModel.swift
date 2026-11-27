import Foundation
import Observation
import RegionKit
import WhereCore

/// Holds a catalog projection and optional place labels for one visible year.
/// Every refresh publishes only while its complete input remains current.
@MainActor
@Observable
final class ElsewhereModel {
    struct Content {
        let report: ElsewhereReport
        var placeNames: [Region: String]
        let cardLocations: RegionCardLocations

        init(report: ElsewhereReport) {
            self.report = report
            placeNames = [:]
            cardLocations = RegionCardLocations(report: report)
        }

        var regions: [ElsewhereRegion] {
            Region.rankedByDayCount(report.regions, days: { $0.days.count }, region: \.region)
        }
    }

    private enum State {
        case idle
        case loading(ElsewhereInput, previous: Content?)
        case naming(ElsewhereInput, Content)
        case loaded(ElsewhereInput, Content)
        case failed(ElsewhereInput, previous: Content?, error: Error)

        var content: Content? {
            switch self {
                case .idle: nil
                case let .loading(_, previous), let .failed(_, previous, _): previous
                case let .loaded(_, content), let .naming(_, content): content
            }
        }
    }

    private var state: State = .idle
    private var requestSequence: UInt64 = 0
    private var knownPlaces: [Coordinate: String] = [:]
    private let resolver: any ElsewhereResolving
    private let namer: any PlaceNaming
    private static let logger = WhereLog.session(ElsewhereModelLog.self)

    init(resolver: any ElsewhereResolving, namer: any PlaceNaming) {
        self.resolver = resolver
        self.namer = namer
    }

    func content(for year: Int) -> Content? {
        guard state.content?.report.year == year else { return nil }
        return state.content
    }

    func failure(for year: Int) -> Error? {
        guard case let .failed(input, _, error) = state,
              input.report.year == year else { return nil }
        return error
    }

    func invalidate() {
        requestSequence += 1
        state = .idle
    }

    func refresh(_ input: ElsewhereInput) async {
        guard !Task.isCancelled else { return }
        if case let .loaded(loadedInput, _) = state, loadedInput == input { return }
        requestSequence += 1
        let sequence = requestSequence
        let previous = content(for: input.report.year)
        let previousState = state
        state = .loading(input, previous: previous)
        let resolved: ElsewhereReport
        do {
            resolved = try await resolver.resolve(input)
            try Task.checkCancellation()
        } catch is CancellationError {
            if requestSequence == sequence { state = previousState }
            return
        } catch {
            guard requestSequence == sequence, !Task.isCancelled else { return }
            Self.logger.loadFailed(error: .restricted(.errorDetails, error))
            state = .failed(input, previous: previous, error: error)
            return
        }
        guard requestSequence == sequence else { return }
        var content = Content(report: resolved)
        state = .naming(input, content)
        for region in content.regions {
            guard let coordinate = region.representativeCoordinate else { continue }
            let name = await placeName(for: coordinate)
            guard requestSequence == sequence, !Task.isCancelled else { return }
            content.placeNames[region.region] = name
            state = .naming(input, content)
        }
        state = .loaded(input, content)
    }

    func cachedPlaceName(for coordinate: Coordinate) -> String? {
        knownPlaces[coordinate]
    }

    func placeName(for coordinate: Coordinate) async -> String? {
        guard !Task.isCancelled else { return nil }
        if let name = knownPlaces[coordinate] { return name }
        let sequence = requestSequence
        let name = await namer.name(for: coordinate)
        guard requestSequence == sequence, !Task.isCancelled else { return nil }
        knownPlaces[coordinate] = name
        return name
    }
}
