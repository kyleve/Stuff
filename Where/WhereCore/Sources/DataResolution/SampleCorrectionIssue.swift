import Foundation

/// An actionable GPS issue. Pending and completed-without-changes reviews never
/// enter the issue badge or notification count.
public struct SampleCorrectionIssue: DataIssue {
    public let proposal: SampleCorrectionProposal
    public init(proposal: SampleCorrectionProposal) {
        self.proposal = proposal
    }

    public var id: DataIssueID {
        proposal.reviewID
    }

    public var category: DataIssueCategory {
        switch id {
            case .flightDay: .flightDay
            case .borderDrift: .borderDrift
            case .missingDays, .abruptChange:
                preconditionFailure("A sample correction must have a GPS issue identity")
        }
    }

    public var sortKey: CalendarDay {
        proposal.day.day
    }

    public var isDismissible: Bool {
        true
    }

    public var resolution: IssueResolution {
        .correctSamples(proposal)
    }
}
