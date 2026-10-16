#if DEBUG
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Each capture configuration gets its own demo world, navigation, and artwork readiness.
    @MainActor
    final class AdaptiveHistorySnapshotFixture {
        static let browseColumn = SnapshotConfiguration.Frame.fullContent(
            name: "browseColumn",
            width: WhereStylesheet.default.adaptiveHistory.minimumControlsWidth,
            minimumHeight: 669,
            layoutTraits: .init(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                interfaceIdiom: .phone,
            ),
        )
        static let historyColumn = SnapshotConfiguration.Frame.fullContent(
            name: "historyColumn",
            width: WhereStylesheet.default.adaptiveHistory.minimumHistoryWidth,
            minimumHeight: 669,
            layoutTraits: .init(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                interfaceIdiom: .phone,
            ),
        )

        enum Selection: Equatable {
            case none
            case region
            case stay
            case month(CalendarDay)
            case settings
        }

        let model = AdaptiveHistoryLabModel()
        let artwork = RegionOutlinePathCache()
        private let selection: Selection
        private var didSelect = false

        init(tab: SceneNavigationModel.TabID, selection: Selection) {
            model.navigation.selectedTab = tab
            self.selection = selection
        }

        func prepare() async {
            await model.load()
            while case .loading = model.state {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }
            guard case let .loaded(world) = model.state else { return }
            if !didSelect {
                didSelect = true
                switch selection {
                    case .none: break
                    case .region:
                        model.navigation.locations.select(region: .california)
                    case .stay:
                        if let report = world.report.report,
                           let stint = PresenceTimeline.stints(
                               from: report,
                               calendar: world.report.calendar,
                           ).first
                        {
                            model.navigation.year.history.select(
                                stint: stint,
                                dateCalendar: world.report.calendar,
                            )
                        }
                    case let .month(month):
                        model.navigation.year.history.select(
                            month: month,
                            dateCalendar: world.report.calendar,
                        )
                    case .settings:
                        model.navigation.settings.selectedRoute = SettingsRoute(.appearance)
                }
            }
            for region in LocationsBackgroundArtwork.regions(in: world.report.ranking) {
                _ = await artwork.path(for: region, resolution: .small)
                _ = await artwork.path(for: region, resolution: .medium)
                _ = await artwork.path(for: region, resolution: .micro)
            }
        }
    }

    #Preview {
        AdaptiveHistorySnapshotScene(
            fixture: AdaptiveHistorySnapshotFixture(tab: .locations, selection: .region),
            pose: .innerPortrait,
        )
        .whereBroadwayRoot()
        .snapshotTraits(SnapshotConfiguration(device: .duoInnerPortrait))
    }

    struct AdaptiveHistorySnapshotScene: View {
        let fixture: AdaptiveHistorySnapshotFixture
        let pose: AdaptiveHistoryPose

        var body: some View {
            Group {
                switch fixture.model.state {
                    case .idle, .loading:
                        ProgressView(String(localized: .primaryLoading))
                    case let .loaded(world):
                        MainTabs(world: world, navigation: fixture.model.navigation)
                            .environment(world.model)
                            .environment(world.session)
                            .environment(\.isInDemoMode, true)
                            .environment(\.demoExitPresentation, .embedded)
                            .environment(\.regionOutlinePathCache, fixture.artwork)
                    case let .failed(error):
                        ContentUnavailableView(
                            String(localized: .commonLoadErrorTitle),
                            systemSymbol: .exclamationmarkTriangle,
                            description: Text(error.localizedDescription),
                        )
                }
            }
            .adaptiveHistoryReservedRegions(pose.regions)
            .task { await fixture.prepare() }
        }
    }
#endif
