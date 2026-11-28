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

    init(review: GPSCorrectionReview, report: YearReportModel) {
        self.report = report
        _model = State(initialValue: FlightReviewModel(review: review, report: report))
    }

    var body: some View {
        Form {
            if let review = model.review {
                ReviewedFlightsSection(review: review, report: report)

                if !model.mapData.pins.isEmpty || !model.mapData.routes.isEmpty {
                    Section {
                        RecordedPointsMap(data: model.mapData)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if let flight = review.flight {
                    FlightEvidenceSection(flight: flight)
                }

                if let proposal = review.proposal {
                    FlightChangesSection(proposal: proposal, model: model)
                }

                if !review.flights.isEmpty, !model.recordedPoints.isEmpty {
                    RecordedFlightPointsSection(model: model)
                }
            } else {
                Section {
                    Label(String(localized: .flightReviewUnavailable), systemSymbol: .infoCircle)
                }
            }

            FlightSaveStatus(model: model)

            if model.review?.proposal != nil {
                Section {
                    ApplyFlightReviewButton(model: model)
                }
            }

            FlightManualEditSection(model: model, report: report)
        }
        .navigationTitle(model.initialDay.displayDate
            .formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            String(localized: .flightReviewPointConfirmTitle),
            isPresented: $model.isConfirmingPointCorrection,
            titleVisibility: .visible,
            presenting: model.pointConfirmation,
        ) { correction in
            Button(correction.action.title) {
                Task { await model.applyPointCorrection(correction) }
            }
        } message: { correction in
            Text(correction.action.confirmationMessage)
        }
        .task(id: report.dataIssueScanInputs) {
            model.receive(report.dataIssueScan)
        }
        .refreshable { await report.rescanForIssues() }
    }
}

private struct ReviewedFlightsSection: View {
    let review: GPSCorrectionReview
    let report: YearReportModel

    var body: some View {
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
    }
}

private struct FlightEvidenceSection: View {
    let flight: FlightAssessment

    var body: some View {
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
}

private struct FlightChangesSection: View {
    let proposal: SampleCorrectionProposal
    let model: FlightReviewModel

    var body: some View {
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
                    EditedFlightPoint(point: point, model: model)
                }
            }
            Text(String(localized: .flightReviewChangesDescription))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordedFlightPointsSection: View {
    let model: FlightReviewModel

    var body: some View {
        Section {
            DisclosureGroup(String(localized: .flightReviewPointsCount(model
                    .recordedPoints.count)))
            {
                ForEach(model.recordedPoints) { point in
                    FlightReviewPointRow(
                        point: point,
                        select: model.selectPointCorrection,
                    )
                    .disabled(!model.canEditPoints)
                }
            }
        } header: {
            Text(String(localized: .flightReviewPointsTitle))
        } footer: {
            Text(String(localized: .flightReviewPointsDescription))
        }
    }
}

private struct ApplyFlightReviewButton: View {
    @Environment(\.dismiss) private var dismiss
    let model: FlightReviewModel

    var body: some View {
        Button(String(localized: .flightReviewApply)) {
            Task {
                await model.apply()
                if model.saveState == .applied {
                    dismiss()
                }
            }
        }
        .disabled(!model.canApply)
        .accessibilityIdentifier("where_flight_apply")
    }
}

private struct FlightManualEditSection: View {
    let model: FlightReviewModel
    let report: YearReportModel

    var body: some View {
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
}

#if DEBUG
    extension FlightDayDetailView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for state in FlightReviewPreviewState.allCases {
                whereSnapshot(
                    name: state == .ready ? "Default" : state.rawValue,
                    configurations: configurations(for: state),
                    // The review is seeded; the fixture report has no later scan to publish.
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        FlightDayDetailView(
                            review: PreviewSupport.flightReview(state: state),
                            report: PreviewSupport.loadedYearReportModel(),
                        )
                    }
                }
            }
            let mixed = PreviewSupport.mixedFlightReview()
            for review in [mixed, mixed.dismissingProposal()].compactMap(\.self) {
                whereSnapshot(
                    name: review.proposal == nil ? "MixedFlightsDismissed" : "MixedFlights",
                    // The multi-flight evidence/actions layout is a second representative.
                    configurations: review
                        .proposal == nil ? .fullContentPhoneLightDark :
                        .fullContentScreenRepresentative,
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack {
                        FlightDayDetailView(
                            review: review,
                            report: PreviewSupport.loadedYearReportModel(),
                        )
                    }
                }
            }
        }

        private static func configurations(for state: FlightReviewPreviewState)
            -> [SnapshotConfiguration]
        {
            switch state {
                case .ready: .fullContentScreenRepresentative
                case .uncertainArrival:
                    .fullContentPhoneLightDarkWithAX5AndAnnotations
                case .flightLikely, .waiting, .stale, .noPresence,
                     .completed: .fullContentPhoneLightDark
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
