import SwiftUI

/// Which outer corners and list gaps a journey-card segment owns.
enum PresenceJourneyCardPosition {
    case standalone
    case top
    case bottom

    func shape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: roundsTop ? cornerRadius : 0,
            bottomLeadingRadius: roundsBottom ? cornerRadius : 0,
            bottomTrailingRadius: roundsBottom ? cornerRadius : 0,
            topTrailingRadius: roundsTop ? cornerRadius : 0,
        )
    }

    var gapEdges: Edge.Set {
        switch self {
            case .standalone:
                [.top, .bottom]
            case .top:
                .top
            case .bottom:
                .bottom
        }
    }

    var joinedEdge: Edge.Set {
        switch self {
            case .standalone:
                []
            case .top:
                .bottom
            case .bottom:
                .top
        }
    }

    private var roundsTop: Bool {
        switch self {
            case .standalone, .top:
                true
            case .bottom:
                false
        }
    }

    private var roundsBottom: Bool {
        switch self {
            case .standalone, .bottom:
                true
            case .top:
                false
        }
    }
}
