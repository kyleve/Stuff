#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI

    struct DeviceLayoutLabPreview: View {
        let model: WhereDemoWorldModel
        let configuration: DeviceLayoutConfiguration
        let initialRegion: Region?

        @Environment(\.stylesheet) private var stylesheet
        /// Forward the live appearance into the synthetic UIKit and SwiftUI trait host.
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            GeometryReader { proxy in
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
                DeviceLayoutLabScreen(model: model, initialRegion: initialRegion)
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

    private struct DeviceLayoutLabScreen: View {
        let model: WhereDemoWorldModel
        let initialRegion: Region?

        var body: some View {
            switch model.state {
                case .idle, .loading:
                    ProgressView(String(localized: .primaryLoading))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(world):
                    DeviceLayoutLabTabs(world: world, initialRegion: initialRegion)
                case let .failed(error):
                    DeviceLayoutLabFailure(error: error, retry: model.retry)
            }
        }
    }

    private struct DeviceLayoutLabTabs: View {
        let world: WhereFlyoverWorld
        let initialRegion: Region?

        var body: some View {
            MainTabs(world: world, region: initialRegion)
                .environment(world.model)
                .environment(world.session)
                .environment(\.isInDemoMode, true)
                .environment(\.demoExitPresentation, .embedded)
        }
    }

    private struct DeviceLayoutLabFailure: View {
        let error: any Error
        let retry: () -> Void

        var body: some View {
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
                    action: retry,
                )
            }
        }
    }

    #Preview { DeviceLayoutLabView.snapshotPreviews }
#endif
