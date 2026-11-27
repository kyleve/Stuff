import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// The optional tab for named visits outside the configured primary regions.
struct ElsewhereView: View {
    let report: YearReportModel
    var isSelected = true
    var makeModel: (() -> ElsewhereModel)?

    var body: some View {
        ObservableHostingView(makeModel ?? {
            ElsewhereModel(resolver: report.services.elsewhere, namer: LocationNamer())
        }) { model in
            ElsewhereNavigation(report: report, model: model, isSelected: isSelected)
        }
    }
}

private struct ElsewhereNavigation: View {
    let report: YearReportModel
    let model: ElsewhereModel
    var isSelected: Bool

    @State private var retrySequence = 0
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.regionStyles) private var regionStyles

    private var isVisible: Bool {
        isSelected && scenePhase != .background
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
        .environment(\.isElsewhereVisible, isVisible)
        .modifier(ElsewhereRefresh(
            report: report,
            model: model,
            isVisible: isVisible,
            retrySequence: retrySequence,
        ))
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
                                            retry: retry,
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
                                            recordedPoints: content.cardLocations
                                                .pointsByRegion[item.region] ?? [],
                                            showsRecordedPoints: report.showsRecordedLocationDots,
                                            recordedPointsID: content.cardLocations.id,
                                        )
                                    }
                                    .buttonStyle(stylesheet.card[.elsewhere].buttonStyle(
                                        tint: regionStyles.style(for: item.region).tint,
                                    ))
                                }
                            }
                        }
                    }
                }
                .padding()
                .whereContentRoot()
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .scrollBounceBehavior(.basedOnSize)
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
        Button(String(localized: .commonRetry), action: retry)
            .buttonStyle(.bordered)
    }

    private func retry() {
        retrySequence += 1
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: .secondaryEmptyTitle), systemSymbol: .globeAmericas)
        } description: {
            Text(String(localized: .secondaryEmptyDescription))
        }
    }
}

extension EnvironmentValues {
    @Entry var isElsewhereVisible = true
}

/// Drives one projection for the entire flow, including pushed detail.
struct ElsewhereRefresh: ViewModifier {
    let report: YearReportModel
    let model: ElsewhereModel
    var isVisible = true
    var retrySequence = 0

    private struct Request: Hashable {
        let year: Int
        let input: ElsewhereInput?
        let isVisible: Bool
        let retrySequence: Int
    }

    func body(content: Content) -> some View {
        let request = Request(
            year: report.selectedYear,
            input: report.elsewhereInput,
            isVisible: isVisible,
            retrySequence: retrySequence,
        )
        content.task(id: request) {
            guard !Task.isCancelled, report.selectedYear == request.year else { return }
            model.prepare(for: request.year)
            guard request.isVisible else { return }
            if case .failed = report.loadState { await report.refresh() }
            guard !Task.isCancelled, report.selectedYear == request.year,
                  let input = report.elsewhereInput else { return }
            await model.refresh(input)
        }
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
                    if let input = report.elsewhereInput { await model.refresh(input) }
                },
                prepareForCapture: {
                    await PreviewSupport.loadCardArtwork(
                        for: model.content(for: report.selectedYear)?.regions.map(\.region) ?? [],
                        cache: cache,
                    )
                },
            ) {
                ElsewhereView(report: report, makeModel: { model })
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
