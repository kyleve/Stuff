import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Shared, static flight status used on Locations and in correction review.
struct FlightStatusBanner: View {
    let review: GPSCorrectionReview
    let deviceLabel: String?
    private let flight: FlightAssessment?

    init(review: GPSCorrectionReview, deviceLabel: String?, flight: FlightAssessment? = nil) {
        self.review = review
        self.deviceLabel = deviceLabel
        self.flight = flight ?? review.flight
    }

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.flightStatus
        VStack(alignment: .leading, spacing: style.spacing) {
            Label(title, systemSymbol: flight == nil ? .locationCircle : .airplane)
                .font(style.titleFont)
            Text(explanation)
                .font(style.bodyFont)
                .foregroundStyle(.secondary)
            if let flight {
                if let deviceLabel {
                    Text(deviceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: .flightStatusLastObservation(
                    flight.lastObservationAt
                        .formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                )))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.padding)
        .background(style.background, in: RoundedRectangle(cornerRadius: style.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if let flight {
            switch flight.progress {
                case .flightLikely: return String(localized: .flightStatusLikelyTitle)
                case .awaitingArrival: return String(localized: .flightStatusWaitingTitle)
                case let .completed(arrival):
                    if arrival
                        .isTimingUncertain { return String(localized: .flightStatusUncertainTitle) }
            }
        }
        return switch review.state {
            case .pending: String(localized: .flightStatusArrivalTitle)
            case .ready: String(localized: .flightStatusReadyTitle)
            case .completed: String(localized: .flightStatusCompletedTitle)
        }
    }

    private var explanation: String {
        if let flight {
            switch flight.progress {
                case .flightLikely: return String(localized: .flightStatusLikelyDescription)
                case .awaitingArrival: return String(localized: .flightStatusWaitingDescription)
                case let .completed(arrival):
                    if arrival
                        .isTimingUncertain
                    {
                        return String(localized: .flightStatusUncertainDescription)
                    }
            }
        }
        return switch review.state {
            case .pending: String(localized: .flightStatusArrivalDescription)
            case .ready: String(localized: .flightStatusReadyDescription)
            case .completed: String(localized: .flightStatusCompletedDescription)
        }
    }
}

#if DEBUG
    extension FlightStatusBanner: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // NoPresence has identical banner content to Ready; the detail screen owns its
            // differences.
            for state in FlightReviewPreviewState.allCases where state != .noPresence {
                whereSnapshot(
                    name: state.rawValue,
                    configurations: state == .uncertainArrival ? .componentRepresentative :
                        .componentLightDark,
                ) {
                    FlightStatusBanner(
                        review: PreviewSupport.flightReview(state: state),
                        deviceLabel: String(localized: .flightStatusDeviceCurrent),
                    )
                    .padding()
                    .background(.background)
                }
            }
            let mixed = PreviewSupport.mixedFlightReview()
            for review in [mixed, mixed.dismissingProposal()].compactMap(\.self) {
                whereSnapshot(
                    name: review.proposal == nil ? "MixedFlightsDismissed" : "MixedFlights",
                    // Multiple banners have a distinct wrapping and accessibility layout.
                    configurations: review
                        .proposal == nil ? .componentLightDark : .componentRepresentative,
                ) {
                    VStack {
                        ForEach(review.flights) { flight in
                            FlightStatusBanner(
                                review: review,
                                deviceLabel: String(localized: .flightStatusDeviceCurrent),
                                flight: flight,
                            )
                        }
                    }
                    .padding()
                    .background(.background)
                }
            }
        }
    }

    #Preview {
        FlightStatusBanner.snapshotPreviews
    }
#endif
