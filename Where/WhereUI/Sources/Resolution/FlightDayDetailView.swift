import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Shared flight/drift review. Pending evidence leaves manual editing available;
/// Apply submits only the exact reviewed samples to Core's guarded transaction.
struct FlightDayDetailView: View {
    let report: YearReportModel
    @State private var model: FlightReviewModel
    @Environment(\.dismiss) private var dismiss

    init(review: GPSCorrectionReview, report: YearReportModel) {
        self.report = report
        _model = State(initialValue: FlightReviewModel(review: review, report: report))
    }

    var body: some View {
        Form {
            if let review = model.review {
                Section {
                    if review.flights.isEmpty {
                        FlightStatusBanner(review: review, deviceLabel: nil)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(review.flights) { flight in
                            FlightStatusBanner(
                                review: review,
                                deviceLabel: report.flightDeviceLabel(flight),
                                flight: flight,
                            )
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }

                if !model.mapPoints.isEmpty {
                    Section {
                        RecordedPointsMap(points: model.mapPoints)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if let flight = review.flight {
                    Section(String(localized: .flightReviewEvidenceTitle)) {
                        LabeledContent(String(localized: .flightReviewPeakSpeed)) {
                            Text(
                                Measurement(
                                    value: flight.peakSpeedKMH,
                                    unit: UnitSpeed.kilometersPerHour,
                                ),
                                format: .measurement(width: .abbreviated, usage: .asProvided),
                            )
                        }
                        Text(String(localized: .flightReviewEvidenceDescription))
                            .foregroundStyle(.secondary)
                    }
                }

                if let proposal = review.proposal {
                    Section(String(localized: .flightReviewChangesTitle)) {
                        LabeledContent(String(localized: .flightReviewResultingRegions)) {
                            Text(proposal.resultingRegions.isEmpty
                                ? String(localized: .flightReviewNoPresence)
                                : proposal.resultingRegions.map(\.localizedName).sorted()
                                .joined(separator: ", "))
                        }
                        DisclosureGroup(String(localized: .flightReviewChangeCount(proposal.edits
                                .count)))
                        {
                            ForEach(model.editedPoints, id: \.sample.id) { point in
                                VStack(alignment: .leading) {
                                    Text(
                                        point.sample.timestamp,
                                        format: .dateTime.hour().minute().second(),
                                    )
                                    Text(model.replacementDescription(for: point.sample.id))
                                        .foregroundStyle(.secondary)
                                    if let speed = WhereFormat
                                        .recordedFlightSpeed(point.sample.motion?.speed)
                                    {
                                        Text(speed)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let altitude = WhereFormat
                                        .recordedFlightAltitude(point.sample.motion?.altitude)
                                    {
                                        Text(altitude)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Text(String(localized: .flightReviewChangesDescription))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Label(String(localized: .flightReviewUnavailable), systemSymbol: .infoCircle)
                }
            }

            switch model.saveState {
                case .idle, .applied:
                    EmptyView()
                case .applying:
                    Section { SavingStatusRow(text: String(localized: .manualSavingStatus)) }
                case .refreshed:
                    Section {
                        Label(
                            String(localized: .flightReviewRefreshed),
                            systemSymbol: .arrowClockwise,
                        )
                    }
                case let .failed(message):
                    Section {
                        Label(message, systemSymbol: .exclamationmarkTriangle)
                    }
            }

            if model.review?.proposal != nil {
                Section {
                    Button(String(localized: .flightReviewApply)) {
                        Task {
                            await model.apply()
                            if model.saveState == .applied { dismiss() }
                        }
                    }
                    .disabled(!model.canApply)
                    .accessibilityIdentifier("where_flight_apply")
                }
            }

            Section {
                NavigationLink {
                    DayRelabelView(day: model.review?.day ?? model.initialDay, report: report)
                } label: {
                    Text(String(localized: .flightReviewManualEdit))
                }
                .disabled(model.saveState == .applying)
            } footer: {
                Text(String(localized: .resolutionFlightManualFixFooter))
            }
        }
        .navigationTitle(model.initialDay.displayDate
            .formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: report.dataIssueScanInputs) {
            model.receive(report.dataIssueScan)
        }
        .refreshable { await report.rescanForIssues() }
    }
}

#if DEBUG
    extension FlightDayDetailView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for state in FlightReviewPreviewState.allCases {
                whereSnapshot(
                    name: state == .ready ? "Default" : state.rawValue,
                    configurations: .fullContentScreenDefaults,
                ) {
                    NavigationStack {
                        FlightDayDetailView(
                            review: PreviewSupport.flightReview(state: state),
                            report: PreviewSupport.loadedYearReportModel(),
                        )
                    }
                }
            }
        }
    }

    #Preview {
        FlightDayDetailView.snapshotPreviews
    }
#endif

#if DEBUG
    extension FlightDayDetailView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            FlightDayDetailView.self,
            title: "Flight Day",
            routes: [.push(to: DayRelabelView.flyoverID)],
        )
    }
#endif
