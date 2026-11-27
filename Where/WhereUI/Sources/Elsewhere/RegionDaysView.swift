import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A named region's resolved visits. Cards, day lists, and map pins use the same
/// projection; corrections receive the original day rather than the inferred name.
struct RegionDaysView: View {
    let region: Region
    let report: YearReportModel
    let model: ElsewhereModel
    @State private var retrySequence = 0

    private struct Request: Hashable {
        let input: ElsewhereInput?
        let retrySequence: Int
    }

    init(region: Region, report: YearReportModel, model: ElsewhereModel? = nil) {
        self.region = region
        self.report = report
        self.model = model ?? report.elsewhere
    }

    private var history: ElsewhereRegion? {
        model.content(for: report.selectedYear)?.report.regions.first { $0.region == region }
    }

    private var failureMessage: String? {
        if case let .failed(error) = report.loadState { return error.message }
        return model.failure(for: report.selectedYear)?.localizedDescription
    }

    private var mapPoints: [RecordedMapPoint] {
        (history?.locations.flatMap(\.points) ?? []).map {
            RecordedMapPoint(
                coordinate: $0.coordinate,
                horizontalAccuracy: $0.horizontalAccuracy,
                region: region,
            )
        }
    }

    var body: some View {
        content
            .navigationTitle(region.localizedName)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: Request(input: report.elsewhereInput, retrySequence: retrySequence)) {
                if case .failed = report.loadState { await report.refresh() }
                if let input = report.elsewhereInput { await model.refresh(input) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let history, !history.days.isEmpty {
            VStack(spacing: 0) {
                if !mapPoints.isEmpty { RecordedPointsMap(points: mapPoints) }
                List {
                    if let failureMessage {
                        Section {
                            Label(
                                failureMessage,
                                systemSymbol: .exclamationmarkIcloud,
                            )
                            retryButton
                        }
                    }
                    Section {
                        ForEach(history.days, id: \.day) { day in
                            NavigationLink {
                                DayRelabelView(day: day, report: report)
                            } label: {
                                DayRow(
                                    day: day,
                                    coordinate: region == .other ? nil : history.locations
                                        .first { $0.day == day.day }?
                                        .points.first?.coordinate,
                                    model: model,
                                )
                            }
                        }
                    } footer: {
                        Text(String(localized: .secondaryRegionFooter))
                    }
                }
                .accessibilityIdentifier("where_region_days_list")
            }
        } else if let failureMessage {
            ContentUnavailableView {
                Label(
                    String(localized: .commonLoadErrorTitle),
                    systemSymbol: .exclamationmarkIcloud,
                )
            } description: {
                Text(failureMessage)
            } actions: {
                retryButton
            }
        } else if model.content(for: report.selectedYear) == nil {
            ProgressView(String(localized: .secondaryLoading))
        } else {
            ContentUnavailableView {
                Label(String(localized: .secondaryRegionEmptyTitle), systemSymbol: .checkmarkCircle)
            } description: {
                Text(String(localized: .secondaryRegionEmptyDescription))
            }
        }
    }

    private var retryButton: some View {
        Button(String(localized: .commonRetry)) { retrySequence += 1 }
    }
}

private struct DayRow: View {
    let day: DayPresence
    let coordinate: Coordinate?
    let model: ElsewhereModel

    @Environment(\.stylesheet) private var stylesheet

    private var placeName: String? {
        coordinate.flatMap { model.cachedPlaceName(for: $0) }
    }

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemSymbol: .calendar)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(day.displayDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.headline)
                if let placeName {
                    Label(placeName, systemSymbol: .mappinAndEllipse)
                        .font(.subheadline)
                }
                Text(WhereFormat
                    .secondaryRegionCurrent(regions: Region.inCanonicalOrder(day.regions)
                        .map(\.localizedName).joined(separator: ", ")))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, stylesheet.spacing.xSmall)
        .task(id: coordinate) {
            guard let coordinate else { return }
            _ = await model.placeName(for: coordinate)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    extension RegionDaysView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let report = PreviewSupport.elsewhereCatalogYearReportModel()
            let model = ElsewhereModel(
                resolver: report.services.elsewhere,
                namer: PreviewPlaceNamer(),
            )
            whereSnapshot(
                name: "WithData",
                configurations: .fullContentScreenRepresentative,
                onReadyToMeasure: {
                    if let input = report.elsewhereInput { await model.refresh(input) }
                },
            ) {
                NavigationStack {
                    RegionDaysView(region: Region(rawValue: "us-NV")!, report: report, model: model)
                }
            }
        }
    }

    #Preview { RegionDaysView.snapshotPreviews }

    extension RegionDaysView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RegionDaysView.self,
            title: "Region Days",
            routes: [.push(to: DayRelabelView.flyoverID)],
        )
    }
#endif
