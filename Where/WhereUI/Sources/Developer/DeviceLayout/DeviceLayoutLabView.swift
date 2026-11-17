#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI

    /// A DEBUG-only mounted production scene. Layout controls keep the demo world; Reset Demo
    /// replaces it.
    struct DeviceLayoutLabView: View {
        @State private var state: DeviceLayoutLabState
        private let initialRegion: Region?

        init(
            state: DeviceLayoutLabState = DeviceLayoutLabState(),
            initialRegion: Region? = nil,
        ) {
            _state = State(initialValue: state)
            self.initialRegion = initialRegion
        }

        @Environment(\.stylesheet) private var stylesheet
        /// Forward the live appearance into the synthetic UIKit and SwiftUI trait host.
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VStack(spacing: stylesheet.spacing.medium) {
                HStack {
                    Text(String(localized: .developerDeviceTitle))
                        .font(.headline)
                    Spacer()
                    Button(String(localized: .developerDeviceReset), action: state.reset)
                        .buttonStyle(.bordered)
                }
                Picker(String(localized: .developerDeviceLayout), selection: $state.configuration) {
                    Section(String(localized: .developerDevicesPhone)) {
                        deviceOptions(idiom: .phone)
                    }
                    Section(String(localized: .developerDevicesTablet)) {
                        deviceOptions(idiom: .pad)
                    }
                    Section(String(localized: .developerDevicesDuo)) {
                        ForEach(SnapshotConfiguration.DuoPose.allCases) { pose in
                            Text(pose.title).tag(DeviceLayoutConfiguration.duo(pose))
                        }
                    }
                }
                .pickerStyle(.menu)
                preview
                    .id(ObjectIdentifier(state.model))
                Text(String(localized: .developerDeviceNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(stylesheet.spacing.medium)
            .background(.background)
            .task(id: state.loadID) { await state.model.load() }
        }

        private func deviceOptions(idiom: SnapshotConfiguration.Frame.LayoutTraits
            .InterfaceIdiom) -> some View
        {
            ForEach(SnapshotConfiguration.DeviceProfile.allCases
                .filter { $0.idiom == idiom })
            { profile in
                ForEach(SnapshotConfiguration.DeviceProfile.Orientation
                    .allCases)
                { orientation in
                    let configuration = DeviceLayoutConfiguration.device(profile, orientation)
                    Text(configuration.title).tag(configuration)
                }
            }
        }

        @ViewBuilder
        private var screen: some View {
            switch state.model.state {
                case .idle, .loading:
                    ProgressView(String(localized: .primaryLoading))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(world):
                    MainTabs(world: world, region: initialRegion)
                        .environment(world.model)
                        .environment(world.session)
                        .environment(\.isInDemoMode, true)
                        .environment(\.demoExitPresentation, .embedded)
                case let .failed(error):
                    ContentUnavailableView {
                        Label(
                            String(localized: .commonLoadErrorTitle),
                            systemSymbol: .exclamationmarkTriangle,
                        )
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button(
                            String(localized: .developerDeviceRetry),
                            action: state.model.retry,
                        )
                    }
            }
        }

        private var preview: some View {
            GeometryReader { proxy in
                let configuration = state.configuration
                let insets = configuration.frame.safeAreaInsets
                let chrome = stylesheet.deviceLayoutLab
                let deviceSize = CGSize(
                    width: configuration.size.width + chrome.bezelWidth * 2,
                    height: configuration.size.height + chrome.bezelWidth * 2,
                )
                let deviceShape = RoundedRectangle(
                    cornerRadius: chrome.screenCornerRadius + chrome.bezelWidth,
                )
                let scale = min(
                    1,
                    min(
                        proxy.size.width / deviceSize.width,
                        proxy.size.height / deviceSize.height,
                    ),
                )
                screen
                    .safeAreaPadding(EdgeInsets(
                        top: insets.top,
                        leading: insets.leading,
                        bottom: insets.bottom,
                        trailing: insets.trailing,
                    ))
                    .frame(width: configuration.size.width, height: configuration.size.height)
                    .background(.background)
                    .adaptivePaneReservedRegions(configuration.regions)
                    .whereBroadwayRoot()
                    .snapshotTraits(SnapshotConfiguration(
                        colorScheme: colorScheme,
                        device: configuration.frame,
                    ))
                    .frame(width: configuration.size.width, height: configuration.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: chrome.screenCornerRadius))
                    .padding(chrome.bezelWidth)
                    .background(chrome.bezelColor, in: deviceShape)
                    .overlay {
                        deviceShape.strokeBorder(.secondary, lineWidth: chrome.outlineWidth)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }

    extension DeviceLayoutLabView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            snapshots(buildWorld: WhereFlyoverWorld.build)
        }

        static func snapshots(
            buildWorld: @escaping @MainActor () async throws -> WhereFlyoverWorld,
        ) -> [SnapshotCase] {
            [
                DeviceLayoutConfiguration.device(.iPhone17, .portrait),
                .device(.iPadPro13, .landscape),
                .duo(.outerPortrait),
                .duo(.tabletop),
            ].flatMap { configuration in
                [ColorScheme.light, .dark].map { colorScheme in
                    let fixture = DuoLayoutSnapshotFixture(
                        tab: .locations,
                        selection: .region,
                        buildWorld: buildWorld,
                    )
                    let layoutName = switch configuration {
                        case .device: configuration.frame.name
                        case let .duo(pose): "duo-" + pose.rawValue
                    }
                    return whereSnapshot(
                        name: colorScheme == .dark ? layoutName + "-dark" : layoutName,
                        configurations: [SnapshotConfiguration(
                            colorScheme: colorScheme,
                            device: .viewport(
                                name: "iPad",
                                size: CGSize(width: 834, height: 1194),
                                layoutTraits: .init(
                                    horizontalSizeClass: .regular,
                                    verticalSizeClass: .regular,
                                    interfaceIdiom: .pad,
                                ),
                                scenePolicy: .retained,
                            ),
                        )],
                        onReadyToSnapshot: { await fixture.prepare() },
                    ) {
                        DeviceLayoutLabView(
                            state: DeviceLayoutLabState(
                                model: fixture.model,
                                configuration: configuration,
                            ),
                            initialRegion: .california,
                        )
                        .environment(\.regionOutlinePathCache, fixture.artwork)
                    }
                }
            }
        }
    }

    #Preview { DeviceLayoutLabView.snapshotPreviews }

    extension DeviceLayoutLabView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            DeviceLayoutLabView.self,
            title: "Device Layout Lab",
            navigationContainer: .none,
        ) { _ in
            DeviceLayoutLabView()
        }
    }
#endif
