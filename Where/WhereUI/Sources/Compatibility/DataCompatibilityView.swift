import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Replaces every data surface while this installation cannot safely consume its store.
struct DataCompatibilityView: View {
    @Environment(\.stylesheet) private var stylesheet
    let state: DataCompatibilityModel.State
    let updates: AppUpdateAvailability
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
                Image(systemSymbol: .arrowDownApp)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(message).foregroundStyle(.secondary)
                if case .updateRequired = state { updateInstructions }
                if case .checking = state {
                    ProgressView(String(localized: .compatibilityChecking))
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
                    DisclosureGroup(String(localized: .compatibilityDiagnostics)) {
                        diagnostics
                    }
                }
            }
            .padding(stylesheet.spacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var title: String {
        switch state {
            case .checking, .compatible: String(localized: .compatibilityChecking)
            case .updateRequired: String(localized: .compatibilityUpdateTitle)
            case .verificationFailed: String(localized: .compatibilityVerificationTitle)
        }
    }

    private var message: String {
        switch state {
            case .checking, .compatible: String(localized: .compatibilityCheckingMessage)
            case .updateRequired: String(localized: .compatibilityUpdateMessage)
            case .verificationFailed: String(localized: .compatibilityVerificationMessage)
        }
    }

    @ViewBuilder private var updateInstructions: some View {
        switch updates {
            case .noBuildsPublished:
                Text(String(localized: .compatibilityNoBuilds))
            case let .published(links):
                switch links {
                    case let .testFlight(url): testFlightLink(url)
                    case let .appStore(url): appStoreLink(url)
                    case let .both(testFlight, appStore):
                        testFlightLink(testFlight)
                        appStoreLink(appStore)
                }
        }
    }

    private func testFlightLink(_ url: URL) -> some View {
        Link(String(localized: .compatibilityTestFlight), destination: url)
    }

    private func appStoreLink(_ url: URL) -> some View {
        Link(String(localized: .compatibilityAppStore), destination: url)
    }

    @ViewBuilder private var diagnostics: some View {
        switch state {
            case let .updateRequired(status), let .compatible(status):
                LabeledContent(String(localized: .compatibilityRequiredVersion)) {
                    Text(status.requiredVersion.rawValue, format: .number)
                }
                LabeledContent(String(localized: .compatibilitySupportedVersion)) {
                    Text(status.supportedVersion.rawValue, format: .number)
                }
            case let .verificationFailed(description):
                Text(description).textSelection(.enabled)
            case .checking: EmptyView()
        }
        if let commit = BuildInfo.current(bundle: .main).commit {
            Text(commit.sha).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}

#if DEBUG
    extension DataCompatibilityView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "UpdateRequired", configurations: .fullContentScreenDefaults) {
                DataCompatibilityView(
                    state: .updateRequired(.init(
                        supportedVersion: .initial,
                        requiredVersion: DataCompatibilityVersion(rawValue: 2),
                    )),
                    updates: .noBuildsPublished,
                    retry: {},
                )
            }
            whereSnapshot(name: "PublishedBuilds", configurations: .fullContentPhoneLightDark) {
                Self(
                    state: .updateRequired(.init(
                        supportedVersion: .initial,
                        requiredVersion: .init(rawValue: 2),
                    )),
                    updates: .published(.both(
                        testFlight: URL(string: "https://example.invalid/testflight")!,
                        appStore: URL(string: "https://example.invalid/app-store")!,
                    )),
                    retry: {},
                )
            }
            whereSnapshot(name: "VerificationFailed", configurations: .fullContentPhoneLightDark) {
                DataCompatibilityView(
                    state: .verificationFailed(
                        description: "The shared requirements could not be read.",
                    ),
                    updates: .noBuildsPublished,
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
