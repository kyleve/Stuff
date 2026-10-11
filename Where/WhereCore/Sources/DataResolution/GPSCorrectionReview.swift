import Foundation
import RegionKit

/// A derived review can explain an ongoing flight before any correction exists.
/// Only a ready state carries an applyable, evidence-bound proposal. A day's
/// ready edits can coexist with unfinished flights in its retained evidence.
public struct GPSCorrectionReview: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case pending(FlightAssessment)
        case ready(SampleCorrectionProposal, flight: FlightAssessment?)
        case completed(FlightAssessment)
    }

    public let id: DataIssueID
    public let day: DayPresence
    public let points: [SampleCorrectionPoint]
    public let state: State
    public let flights: [FlightAssessment]
    public let pointCorrections: [FlightPointCorrection]

    public init(
        id: DataIssueID,
        day: DayPresence,
        points: [SampleCorrectionPoint],
        state: State,
        flights: [FlightAssessment] = [],
        pointCorrections: [FlightPointCorrection] = [],
    ) {
        self.id = id
        self.day = day
        self.points = points
        self.state = state
        self.pointCorrections = pointCorrections
        if flights.isEmpty {
            switch state {
                case let .pending(flight), let .completed(flight): self.flights = [flight]
                case let .ready(_, flight): self.flights = flight.map { [$0] } ?? []
            }
        } else {
            self.flights = flights
        }
    }

    public var flight: FlightAssessment? {
        switch state {
            case let .pending(flight), let .completed(flight): flight
            case let .ready(_, flight): flight
        }
    }

    public var proposal: SampleCorrectionProposal? {
        switch state {
            case let .ready(proposal, _): proposal
            case .pending, .completed: nil
        }
    }

    public var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    /// Dismiss only the actionable suggestion. Unfinished flights on the same
    /// day remain available as information, without a proposal or issue badge.
    public func dismissingProposal() -> Self? {
        guard proposal != nil else { return self }
        guard let pending = flights.last(where: \.isPending) else { return nil }
        return Self(
            id: id,
            day: day,
            points: points,
            state: .pending(pending),
            flights: flights,
            pointCorrections: pointCorrections,
        )
    }
}
