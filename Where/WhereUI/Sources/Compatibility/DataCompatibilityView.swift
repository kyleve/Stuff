import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// History-free recovery shared by cold launch and live session retirement.
struct DataCompatibilityView: View {
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.openURL) private var openURL
    @State private var isRetrying = false
    @AccessibilityFocusState private var titleFocused: Bool
    let state: DataCompatibilityCoordinator.State
    let retry: @MainActor () async -> Void

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
            Image(systemSymbol: .lockIcloud)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(message).foregroundStyle(.secondary)
            if case let .blocked(.updateRequired(_, reason)) = state,
               let explanation = reason?.localized(preferredLocales: Locale.preferredLocales)
            {
                Text(verbatim: explanation).foregroundStyle(.secondary)
            }
            if case .checking = state {
                ProgressView()
            } else {
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
                if case .blocked(.locationPermissionRequired) = state {
                    Button(String(localized: .compatibilityOpenSettings)) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
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

#if DEBUG
    extension DataCompatibilityView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereThemeSnapshot(
                name: "UpdateRequired",
                configurations: .fullContentScreenRepresentative,
                measurementReadiness: .immediate,
            ) {
                Self(
                    state: .blocked(.updateRequired(
                        .init(rawValue: 2),
                        reason: .init(
                            translations: ["en": String(
                                localized: .compatibilityPreviewUpdateReason,
                            )],
                        ),
                    )),
                    retry: {},
                )
            }
            whereThemeSnapshot(
                name: "RecordingDevice",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                Self(state: .blocked(.recordingDeviceRequired), retry: {})
            }
            whereThemeSnapshot(
                name: "Permission",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                Self(state: .blocked(.locationPermissionRequired), retry: {})
            }
            whereThemeSnapshot(
                name: "Verification",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                Self(
                    state: .blocked(.verificationRequired(URLError(.notConnectedToInternet))),
                    retry: {},
                )
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
