#if DEBUG
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Each capture configuration gets its own demo world, navigation, and artwork readiness.
    @MainActor
    final class DuoLayoutSnapshotFixture {
        static let browseColumn = SnapshotConfiguration.Frame.fullContent(
            name: "browseColumn",
            width: WhereStylesheet.default.adaptivePane.minimumControlsWidth,
            minimumHeight: 669,
            layoutTraits: .init(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                interfaceIdiom: .phone,
            ),
        )
        static let historyColumn = SnapshotConfiguration.Frame.fullContent(
            name: "historyColumn",
            width: WhereStylesheet.default.adaptivePane.minimumDetailWidth,
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
            case timeline
            case settings
        }

        let model = DuoLayoutLabModel()
        let artwork = RegionOutlinePathCache()
        let tab: MainTabSelection.TabID
        let selection: Selection

        init(tab: MainTabSelection.TabID, selection: Selection) {
            self.tab = tab
            self.selection = selection
        }

        func prepare() async {
            await model.load()
            while case .loading = model.state {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }
            guard case let .loaded(world) = model.state else { return }
            for region in LocationsBackgroundArtwork.regions(in: world.report.ranking) {
                _ = await artwork.path(for: region, resolution: .small)
                _ = await artwork.path(for: region, resolution: .medium)
                _ = await artwork.path(for: region, resolution: .micro)
            }
        }
    }

    #Preview {
        DuoLayoutSnapshotScene(
            fixture: DuoLayoutSnapshotFixture(tab: .locations, selection: .region),
            pose: .innerPortrait,
        )
        .whereBroadwayRoot()
        .snapshotTraits(SnapshotConfiguration(device: .duoInnerPortrait))
    }

    struct DuoLayoutSnapshotScene: View {
        let fixture: DuoLayoutSnapshotFixture
        let pose: SnapshotConfiguration.Pose

        var body: some View {
            Group {
                switch fixture.model.state {
                    case .idle, .loading:
                        ProgressView(String(localized: .primaryLoading))
                    case let .loaded(world):
                        MainTabs(
                            world: world,
                            tab: fixture.tab,
                            region: fixture.selection == .region ? .california : nil,
                            settingsRoute: fixture
                                .selection == .settings ? SettingsRoute(.appearance) : nil,
                            yearMode: fixture.selection == .timeline ? .timeline : .calendar,
                        )
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
            .adaptivePaneReservedRegions(pose.regions)
            .task { await fixture.prepare() }
        }
    }
#endif
