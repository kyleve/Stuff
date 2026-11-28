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

        var body: some View {
            VStack(spacing: stylesheet.spacing.medium) {
                DeviceLayoutLabHeader(reset: state.reset)
                DeviceLayoutLabPicker(configuration: $state.configuration)
                DeviceLayoutLabPreview(
                    model: state.model,
                    configuration: state.configuration,
                    initialRegion: initialRegion,
                )
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

    private struct DeviceLayoutLabHeader: View {
        let reset: () -> Void

        var body: some View {
            HStack {
                Text(String(localized: .developerDeviceTitle))
                    .font(.headline)
                Spacer()
                Button(String(localized: .developerDeviceReset), action: reset)
                    .buttonStyle(.bordered)
            }
        }
    }

    private struct DeviceLayoutLabPicker: View {
        @Binding var configuration: DeviceLayoutConfiguration

        var body: some View {
            Picker(String(localized: .developerDeviceLayout), selection: $configuration) {
                Section(String(localized: .developerDevicesPhone)) {
                    DeviceLayoutOptions(idiom: .phone)
                }
                Section(String(localized: .developerDevicesTablet)) {
                    DeviceLayoutOptions(idiom: .pad)
                }
                Section(String(localized: .developerDevicesDuo)) {
                    ForEach(SnapshotConfiguration.DuoPose.allCases) { pose in
                        Text(pose.title).tag(DeviceLayoutConfiguration.duo(pose))
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }

    private struct DeviceLayoutOptions: View {
        let idiom: SnapshotConfiguration.Frame.LayoutTraits.InterfaceIdiom

        var body: some View {
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
    }
#endif
