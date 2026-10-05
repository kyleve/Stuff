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
                case .completed: break
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
                case .completed: break
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
            for state in FlightReviewPreviewState.allCases {
                whereSnapshot(
                    name: state.rawValue,
                    configurations: .fullContentScreenDefaults,
                ) {
                    NavigationStack {
                        ScrollView {
                            FlightStatusBanner(
                                review: PreviewSupport.flightReview(state: state),
                                deviceLabel: String(localized: .flightStatusDeviceCurrent),
                            )
                            .padding()
                        }
                        .navigationTitle(String(localized: .tabLocations))
                    }
                }
            }
            let mixed = PreviewSupport.mixedFlightReview()
            for review in [mixed, mixed.dismissingProposal()].compactMap(\.self) {
                whereSnapshot(
                    name: review.proposal == nil ? "MixedFlightsDismissed" : "MixedFlights",
                    configurations: .fullContentScreenDefaults,
                ) {
                    NavigationStack {
                        ScrollView {
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
                        }
                        .navigationTitle(String(localized: .tabLocations))
                    }
                }
            }
        }
    }

    #Preview {
        FlightStatusBanner.snapshotPreviews
    }
#endif
