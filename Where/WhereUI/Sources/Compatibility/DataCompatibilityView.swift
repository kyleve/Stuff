import InstallerKit
import SnapshotKit
import SwiftUI
import WhereCore
#if DEBUG
    @_spi(Testing) import InstallerKitUI
#endif

/// History-free recovery shared by cold launch and live session retirement.
struct DataCompatibilityView: View {
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.isInDemoMode) private var isInDemoMode
    @Environment(\.primaryAppIconName) private var primaryAppIconName
    @Environment(UpdateModel.self) private var updates: UpdateModel?
    @State private var isRetrying = false
    @AccessibilityFocusState private var titleFocused: Bool
    let state: DataCompatibilityCoordinator.State
    private let previewImageName: String?
    let retry: @MainActor () async -> Void

    init(
        state: DataCompatibilityCoordinator.State,
        previewImageName: String? = nil,
        retry: @escaping @MainActor () async -> Void,
    ) {
        self.state = state
        self.previewImageName = previewImageName
        self.retry = retry
    }

    private var title: LocalizedStringResource {
        switch state {
            case .checking, .allowed, .offline: .compatibilityCheckingTitle
            case .blocked(.updateRequired): .compatibilityUpdateTitle
            case .blocked(.recordingDeviceRequired): .compatibilityRecordingTitle
            case .blocked(.locationPermissionRequired): .compatibilityPermissionTitle
            case .blocked(.verificationRequired): .compatibilityVerificationTitle
        }
    }

    private var message: LocalizedStringResource {
        switch state {
            case .checking, .allowed, .offline: .compatibilityCheckingMessage
            case .blocked(.updateRequired): .compatibilityUpdateMessage
            case .blocked(.recordingDeviceRequired): .compatibilityRecordingMessage
            case .blocked(.locationPermissionRequired): .compatibilityPermissionMessage
            case .blocked(.verificationRequired): .compatibilityVerificationMessage
        }
    }

    var body: some View {
        VStack(spacing: stylesheet.spacing.large) {
            AppIconImage(
                name: previewImageName ?? AppIconCatalog
                    .liveSelectedPreviewImageName(primaryAppIconName: primaryAppIconName),
                size: stylesheet.size.compatibilityIcon,
                bordered: false,
            )
            Text(title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(message).foregroundStyle(.secondary)
            if case let .blocked(.updateRequired(_, reason)) = state,
               let explanation = reason?.localized(preferredLocales: Locale.preferredLocales)
            {
                CompatibilityUpdateReason(explanation: explanation)
            }
            if case .checking = state {
                ProgressView()
            } else if case .blocked(.updateRequired) = state {
                if !isInDemoMode, let updates {
                    CompatibilityAppUpdatesButton(model: updates)
                }
            } else {
                CompatibilityRetryButton(isRetrying: $isRetrying, retry: retry)
                if case .blocked(.locationPermissionRequired) = state {
                    CompatibilityOpenSettingsButton()
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .whereScreenRoot()
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .background(FeatureDiscoveryBackground())
        .task { titleFocused = true }
    }
}

private struct CompatibilityAppUpdatesButton: View {
    let model: UpdateModel
    @State private var showsUpdates = false

    var body: some View {
        Button(String(localized: .updatesTitle)) { showsUpdates = true }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .sheet(isPresented: $showsUpdates) {
                CompatibilityUpdatesSheet(model: model) { showsUpdates = false }
            }
    }
}

private struct CompatibilityUpdateReason: View {
    let explanation: String

    var body: some View {
        GroupBox {
            Text(verbatim: explanation)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
        } label: {
            Text(.compatibilityUpdateReasonTitle)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct CompatibilityRetryButton: View {
    @Binding var isRetrying: Bool
    let retry: @MainActor () async -> Void

    var body: some View {
        Button(String(localized: .compatibilityRetry)) {
            isRetrying = true
            Task {
                await retry()
                isRetrying = false
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isRetrying)
    }
}

private struct CompatibilityOpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(String(localized: .compatibilityOpenSettings)) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
    }
}

private struct CompatibilityUpdatesSheet: View {
    let model: UpdateModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            DevelopmentUpdatesView(model: model, focus: nil)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { done() }
                    }
                }
        }
    }
}

#if DEBUG
    extension DataCompatibilityView: SnapshotProviding {
        private static func preview(state: DataCompatibilityCoordinator.State) -> Self {
            Self(state: state, previewImageName: "AppIconClassic", retry: {})
        }

        private static var previewUpdateRequiredState: DataCompatibilityCoordinator.State {
            .blocked(.updateRequired(
                .init(rawValue: 2),
                reason: .init(
                    translations: ["en": String(localized: .compatibilityPreviewUpdateReason)],
                ),
            ))
        }

        static var snapshots: [SnapshotCase] {
            whereThemeSnapshot(
                name: "UpdateRequired",
                configurations: .fullContentScreenRepresentative,
                measurementReadiness: .immediate,
            ) {
                preview(state: previewUpdateRequiredState)
            }
            whereThemeSnapshot(
                name: "UpdateRequiredWithAppUpdates",
                configurations: .fullContentPhoneLightDarkWithAX5,
                measurementReadiness: .immediate,
            ) {
                preview(state: previewUpdateRequiredState)
                    .environment(InstallerPreview.model(.available))
            }
            whereThemeSnapshot(
                name: "RecordingDevice",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                preview(state: .blocked(.recordingDeviceRequired))
            }
            whereThemeSnapshot(
                name: "Permission",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                preview(state: .blocked(.locationPermissionRequired))
            }
            whereThemeSnapshot(
                name: "Verification",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                preview(state: .blocked(.verificationRequired(URLError(.notConnectedToInternet))))
            }
        }
    }

    extension DataCompatibilityView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            Self.self,
            title: "Data Compatibility",
            navigationContainer: .none,
        )
    }

    #Preview { DataCompatibilityView.snapshotPreviews }
#endif
