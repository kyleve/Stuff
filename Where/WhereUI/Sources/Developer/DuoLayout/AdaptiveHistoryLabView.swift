#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI

    /// A DEBUG-only mounted production scene. Pose controls change geometry, never its models.
    struct AdaptiveHistoryLabView: View {
        @State private var model: AdaptiveHistoryLabModel
        @State private var pose: SnapshotConfiguration.Pose
        private let initialRegion: Region?

        init(
            model: AdaptiveHistoryLabModel = AdaptiveHistoryLabModel(),
            pose: SnapshotConfiguration.Pose = .outerPortrait,
            initialRegion: Region? = nil,
        ) {
            _model = State(initialValue: model)
            _pose = State(initialValue: pose)
            self.initialRegion = initialRegion
        }

        @Environment(\.stylesheet) private var stylesheet

        var body: some View {
            VStack(spacing: stylesheet.spacing.medium) {
                Text(String(localized: .developerDuoTitle))
                    .font(.headline)
                Picker(String(localized: .developerDuoPose), selection: $pose) {
                    ForEach(SnapshotConfiguration.Pose.allCases) { pose in
                        Text(pose.title).tag(pose)
                    }
                }
                .pickerStyle(.menu)
                Group {
                    switch model.state {
                        case .idle, .loading:
                            ProgressView(String(localized: .primaryLoading))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case let .loaded(world):
                            preview(world: world)
                        case let .failed(error):
                            ContentUnavailableView {
                                Label(
                                    String(localized: .commonLoadErrorTitle),
                                    systemSymbol: .exclamationmarkTriangle,
                                )
                            } description: {
                                Text(error.localizedDescription)
                            } actions: {
                                Button(String(localized: .developerDuoRetry), action: model.retry)
                            }
                    }
                }
                Text(String(localized: .developerDuoNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(stylesheet.spacing.medium)
            .background(.background)
            .task(id: model.request) { await model.load() }
        }

        private func preview(world: WhereFlyoverWorld) -> some View {
            GeometryReader { proxy in
                let insets = pose.frame.safeAreaInsets
                let scale = min(
                    1,
                    min(proxy.size.width / pose.size.width, proxy.size.height / pose.size.height),
                )
                MainTabs(world: world, region: initialRegion)
                    .environment(world.model)
                    .environment(world.session)
                    .environment(\.isInDemoMode, true)
                    .environment(\.demoExitPresentation, .embedded)
                    .safeAreaPadding(EdgeInsets(
                        top: insets.top,
                        leading: insets.leading,
                        bottom: insets.bottom,
                        trailing: insets.trailing,
                    ))
                    .frame(width: pose.size.width, height: pose.size.height)
                    .background(.background)
                    .adaptiveHistoryReservedRegions(pose.regions)
                    .whereBroadwayRoot()
                    .snapshotTraits(SnapshotConfiguration(device: pose.frame))
                    .frame(width: pose.size.width, height: pose.size.height)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
        }
    }

    extension AdaptiveHistoryLabView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [SnapshotConfiguration.Pose.outerPortrait, .tabletop].map { pose in
                let fixture = AdaptiveHistorySnapshotFixture(tab: .locations, selection: .region)
                return whereSnapshot(
                    name: pose.rawValue,
                    configurations: [SnapshotConfiguration(device: .viewport(
                        name: "iPad",
                        size: CGSize(width: 834, height: 1194),
                        layoutTraits: .init(
                            horizontalSizeClass: .regular,
                            verticalSizeClass: .regular,
                            interfaceIdiom: .pad,
                        ),
                        scenePolicy: .retained,
                    ))],
                    onReadyToSnapshot: { await fixture.prepare() },
                ) {
                    AdaptiveHistoryLabView(
                        model: fixture.model,
                        pose: pose,
                        initialRegion: .california,
                    )
                    .environment(\.regionOutlinePathCache, fixture.artwork)
                }
            }
        }
    }

    #Preview { AdaptiveHistoryLabView.snapshotPreviews }

    extension AdaptiveHistoryLabView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AdaptiveHistoryLabView.self,
            title: "Duo Layout Lab",
            navigationContainer: .none,
        ) { _ in
            AdaptiveHistoryLabView()
        }
    }
#endif
