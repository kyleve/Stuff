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

    @State private var retrySequence = 0
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.scenePhase) private var scenePhase

    private struct Request: Hashable {
        let input: ElsewhereInput?
        let isVisible: Bool
        let retrySequence: Int
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
            retrySequence: retrySequence,
        )
    }

    private var failureMessage: String? {
        if case let .failed(error) = report.loadState { return error.message }
        return model.failure(for: report.selectedYear)?.localizedDescription
    }

    private var backgroundRegions: [Region] {
        let visited = Set(model.content(for: report.selectedYear)?.report.regions
            .map(\.region) ?? [])
        return Region.allCases.filter { visited.contains($0) }
    }

    var body: some View {
        NavigationStack {
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    LocationsBackground(regions: backgroundRegions)
                        .ignoresSafeArea()
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: request) {
            guard request.isVisible else { return }
            if case .failed = report.loadState { await report.refresh() }
            guard let input = report.elsewhereInput, !Task.isCancelled else { return }
            await model.refresh(input)
        }
        .debugLogInspectable(WhereLog.session(ElsewhereModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
        if let content = model.content(for: report.selectedYear) {
            ScrollView {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xLarge) {
                    if let failureMessage {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            Label(failureMessage, systemSymbol: .exclamationmarkIcloud)
                            retryButton
                        }
                    }
                    if content.regions.isEmpty {
                        emptyState
                    } else {
                        GlassEffectContainer(spacing: stylesheet.spacing.large) {
                            VStack(spacing: stylesheet.spacing.large) {
                                ForEach(content.regions) { item in
                                    NavigationLink {
                                        RegionDaysView(
                                            region: item.region,
                                            report: report,
                                            model: model,
                                        )
                                    } label: {
                                        RegionSummaryCard(
                                            regionDays: RegionDays(
                                                region: item.region,
                                                days: item.days.count,
                                            ),
                                            places: content.placeNames[item.region],
                                            variant: .elsewhere,
                                            year: report.selectedYear,
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("where_elsewhere_list")
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
        } else {
            ProgressView(String(localized: .secondaryLoading))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var retryButton: some View {
        Button(String(localized: .commonRetry)) { retrySequence += 1 }
            .buttonStyle(.bordered)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: .secondaryEmptyTitle), systemSymbol: .globeAmericas)
        } description: {
            Text(String(localized: .secondaryEmptyDescription))
        }
    }
}

#if DEBUG
    extension ElsewhereView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshot(
                name: "Loaded",
                report: PreviewSupport.elsewhereCatalogYearReportModel(),
                configurations: .fullContentScreenDefaults,
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
            resolver: (any ElsewhereResolving)? = nil,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            let model = ElsewhereModel(
                resolver: resolver ?? report.services.elsewhere,
                namer: PreviewPlaceNamer(),
            )
            return whereSnapshot(
                name: name,
                configurations: configurations,
                onReadyToMeasure: {
                    if let input = report.elsewhereInput { await model.refresh(input) }
                },
                onReadyToSnapshot: {
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
