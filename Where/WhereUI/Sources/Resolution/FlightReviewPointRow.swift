import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// One recorded GPS point, its flight evidence, and its available reversible decision.
struct FlightReviewPointRow: View {
    let point: FlightReviewPresentation.Point
    let select: (FlightPointCorrection) -> Void
    var body: some View {
        if let correction = point.correction {
            Button { select(correction) } label: {
                FlightReviewPointContent(point: point)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityInputLabels([
                Text(String(localized: .flightReviewPointActionAt(
                    correction.action.title,
                    point.point.sample.timestamp.formatted(.dateTime.hour().minute().second()),
                ))),
                Text(correction.action.title),
            ])
        } else {
            FlightReviewPointContent(point: point)
                .accessibilityElement(children: .combine)
        }
    }
}

extension FlightPointCorrection.Action {
    var title: String {
        switch self {
            case .includeInFlight: String(localized: .flightReviewPointInclude)
            case .restoreGPS: String(localized: .flightReviewPointRestore)
        }
    }

    var confirmationMessage: String {
        switch self {
            case .includeInFlight: String(localized: .flightReviewPointConfirmInclude)
            case .restoreGPS: String(localized: .flightReviewPointConfirmRestore)
        }
    }
}

#if DEBUG
    @_spi(Testing) import WhereCore

    extension FlightReviewPointRow: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let review = PreviewSupport.flightReview(state: .ready)
            let point = review.points[1]
            let include = FlightPointCorrection(
                sampleID: point.sample.id,
                action: .includeInFlight,
                day: review.day.day,
                resultingRegions: [.california, .newYork],
            )
            whereSnapshot(name: "Gap", configurations: .fullContentScreenDefaults) {
                Form {
                    FlightReviewPointRow(point: .init(
                        point: point,
                        evidence: .inferred(.recordingGap(
                            duration: 4 * 3600,
                            averageSpeedKMH: 740,
                        )),
                        correction: include,
                    ), select: { _ in })
                }
            }
            whereSnapshot(name: "Restore", configurations: .fullContentPhoneLightDark) {
                Form {
                    FlightReviewPointRow(point: .init(
                        point: SampleCorrectionPoint(sample: point.sample, regions: []),
                        evidence: .uncertain,
                        correction: FlightPointCorrection(
                            sampleID: point.sample.id,
                            action: .restoreGPS,
                            day: review.day.day,
                            resultingRegions: [.california, .newYork, .other],
                        ),
                    ), select: { _ in })
                }
            }
            whereSnapshot(name: "Ground", configurations: .fullContentPhoneLightDark) {
                Form {
                    FlightReviewPointRow(point: .init(
                        point: review.points[0],
                        evidence: .ground,
                        correction: nil,
                    ), select: { _ in })
                }
            }
        }
    }

    #Preview {
        FlightReviewPointRow.snapshotPreviews
    }
#endif
