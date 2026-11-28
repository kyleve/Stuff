import BroadwayCore
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
    @State private var retryTrigger = EventTrigger()

    private struct Request: Hashable {
        let input: ElsewhereInput?
        let retryTrigger: EventTrigger
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
        if case let .failed(error) = report.loadState {
            return error.message
        }
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
        Group {
            if let history, !history.days.isEmpty {
                RegionDaysList(
                    history: history,
                    region: region,
                    report: report,
                    model: model,
                    mapPoints: mapPoints,
                    failureMessage: failureMessage,
                    retry: { retryTrigger.fire() },
                )
            } else if let failureMessage {
                ElsewhereLoadFailure(message: failureMessage) {
                    Button(String(localized: .commonRetry)) { retryTrigger.fire() }
                }
            } else if model.content(for: report.selectedYear) == nil {
                ProgressView(String(localized: .secondaryLoading))
            } else {
                EmptyRegionDays()
            }
        }

        .navigationTitle(region.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Request(input: report.elsewhereInput, retryTrigger: retryTrigger)) {
            if case .failed = report.loadState {
                await report.refresh()
            }
            if let input = report.elsewhereInput {
                await model.refresh(input)
            }
        }
    }
}

private struct EmptyRegionDays: View {
    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .secondaryRegionEmptyTitle), systemSymbol: .checkmarkCircle)
        } description: {
            Text(String(localized: .secondaryRegionEmptyDescription))
        }
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
                    if let input = report.elsewhereInput {
                        await model.refresh(input)
                    }
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
