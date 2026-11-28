import BroadwayCore
import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// The optional tab for named visits outside the configured primary regions.
struct ElsewhereView: View {
    let report: YearReportModel
    let model: ElsewhereModel
    var isSelected: Bool

    @State private var retryTrigger = EventTrigger()

    @Environment(\.scenePhase) private var scenePhase

    private struct Request: Hashable {
        let input: ElsewhereInput?
        let isVisible: Bool
        let retryTrigger: EventTrigger
    }

    init(report: YearReportModel, model: ElsewhereModel? = nil, isSelected: Bool = true) {
        self.report = report
        self.model = model ?? report.elsewhere
        self.isSelected = isSelected
    }

    private var request: Request {
        Request(
            input: report.elsewhereInput,
            isVisible: isSelected && scenePhase != .background,
            retryTrigger: retryTrigger,
        )
    }

    private var failureMessage: String? {
        if case let .failed(error) = report.loadState {
            return error.message
        }
        return model.failure(for: report.selectedYear)?.localizedDescription
    }

    private var backgroundRegions: [Region] {
        let visited = Set(model.content(for: report.selectedYear)?.report.regions
            .map(\.region) ?? [])
        return Region.allCases.filter { visited.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let content = model.content(for: report.selectedYear) {
                    ElsewhereRegionList(
                        content: content,
                        report: report,
                        model: model,
                        failureMessage: failureMessage,
                        retry: { retryTrigger.fire() },
                    )
                } else if let failureMessage {
                    ElsewhereLoadFailure(message: failureMessage) {
                        ElsewhereRetryButton(retry: { retryTrigger.fire() })
                    }
                } else {
                    ProgressView(String(localized: .secondaryLoading))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LocationsBackground(regions: backgroundRegions)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: request) {
            guard request.isVisible else { return }
            if case .failed = report.loadState {
                await report.refresh()
            }
            guard let input = report.elsewhereInput, !Task.isCancelled else { return }
            await model.refresh(input)
        }
        .debugLogInspectable(WhereLog.session(ElsewhereModelLog.self))
    }
}

#if DEBUG
    extension ElsewhereView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshot(
                name: "Loaded",
                report: PreviewSupport.elsewhereCatalogYearReportModel(),
                configurations: .fullContentScreenRepresentative,
            )
            snapshot(
                name: "FlatLoaded",
                report: PreviewSupport.elsewhereCatalogYearReportModel(),
                configurations: .fullContentPhoneLightDark,
                theme: .alternate,
            )
            let hiddenDots = {
                let report = PreviewSupport.elsewhereCatalogYearReportModel()
                report.showsRecordedLocationDots = false
                return report
            }()
            snapshot(
                name: "DotsHidden",
                report: hiddenDots,
                configurations: .fullContentPhoneLightDark,
            )
            snapshot(
                name: "Empty",
                report: PreviewSupport.emptyYearReportModel(),
                configurations: .fullContentPhoneLightDark,
            )
            snapshot(
                name: "Failure",
                report: PreviewSupport.elsewhereCatalogYearReportModel(),
                configurations: .fullContentPhoneLightDark,
                resolver: FailingElsewhereResolver(),
            )
        }

        private static func snapshot(
            name: String,
            report: YearReportModel,
            configurations: [SnapshotConfiguration],
            theme: WhereTheme = .standard,
            resolver: (any ElsewhereResolving)? = nil,
        ) -> SnapshotCase {
            let cache = PreviewSupport.snapshotArtworkCache
            let model = ElsewhereModel(
                resolver: resolver ?? report.services.elsewhere,
                namer: PreviewPlaceNamer(),
            )
            return whereSnapshot(
                name: name,
                configurations: configurations,
                theme: theme,
                onReadyToMeasure: {
                    if let input = report.elsewhereInput {
                        await model.refresh(input)
                    }
                },
                prepareForCapture: {
                    await PreviewSupport.loadCardArtwork(
                        for: model.content(for: report.selectedYear)?.regions.map(\.region) ?? [],
                        cache: cache,
                    )
                },
            ) {
                ElsewhereView(report: report, model: model)
                    .environment(\.regionOutlinePathCache, cache)
            }
        }
    }

    #Preview { ElsewhereView.snapshotPreviews }

    extension ElsewhereView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            ElsewhereView.self,
            title: "Elsewhere",
            navigationContainer: .none,
            routes: [.push(to: RegionDaysView.flyoverID)],
        )
    }
#endif
