import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A history-free recovery surface. It remains usable before any service scope exists.
struct DataCompatibilityView: View {
    @Environment(\.stylesheet) private var stylesheet

    let state: WhereDataCompatibilityModel.State
    let isChecking: Bool
    let retry: @MainActor () async -> Void

    private var title: String {
        switch state {
            case .updateRequired: String(localized: .compatibilityUpdateTitle)
            case .failed: String(localized: .compatibilityVerifyTitle)
            case .notChecked, .available: String(localized: .compatibilityCheckingTitle)
        }
    }

    private var message: String {
        switch state {
            case .updateRequired: String(localized: .compatibilityUpdateMessage)
            case let .failed(error):
                if error as? DataCompatibilityError == .accountChanged {
                    String(localized: .compatibilityAccountMessage)
                } else {
                    String(localized: .compatibilityVerifyMessage)
                }
            case .notChecked, .available: String(localized: .compatibilityCheckingMessage)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: stylesheet.spacing.large) {
                    Image(systemSymbol: .exclamationmarkIcloud)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .foregroundStyle(.secondary)
                    if isChecking {
                        ProgressView(String(localized: .compatibilityCheckingTitle))
                    } else {
                        Button(String(localized: .compatibilityRetry)) {
                            Task { await retry() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(stylesheet.spacing.xxxLarge)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#if DEBUG
    extension DataCompatibilityView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "UpdateRequired",
                configurations: .fullContentPhoneLightDarkWithAX5,
                measurementReadiness: .immediate,
            ) {
                DataCompatibilityView(
                    state: .updateRequired(requiredMajor: 2),
                    isChecking: false,
                    retry: {},
                )
            }
            whereSnapshot(
                name: "VerificationRequired",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                DataCompatibilityView(
                    state: .failed(DataCompatibilityError.verificationRequired),
                    isChecking: false,
                    retry: {},
                )
            }
            whereSnapshot(
                name: "AccountChanged",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                DataCompatibilityView(
                    state: .failed(DataCompatibilityError.accountChanged),
                    isChecking: false,
                    retry: {},
                )
            }
        }
    }

    #Preview { DataCompatibilityView.snapshotPreviews }

    extension DataCompatibilityView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            DataCompatibilityView.self,
            title: "Data Compatibility",
            navigationContainer: .none,
        )
    }
#endif
