import SnapshotKit
import SwiftUI

/// The signed-out dashboard shell. GitHub-backed sections fill this same
/// navigation structure once onboarding creates an account scope.
@_spi(Testing)
public struct PatchlightDashboardView: View {
    private enum Destination: String, Hashable, CaseIterable, Identifiable {
        case reviewRequested
        case ownPullRequests
        case repositories

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .reviewRequested: String(localized: .reviewRequested)
                case .ownPullRequests: String(localized: .myOpenPullRequests)
                case .repositories: String(localized: .repositories)
            }
        }

        var symbol: String {
            switch self {
                case .reviewRequested: "person.crop.circle.badge.checkmark"
                case .ownPullRequests: "arrow.triangle.pull"
                case .repositories: "shippingbox"
            }
        }
    }

    @Environment(\.patchlightStylesheet) private var stylesheet
    @State private var selection: Destination? = .reviewRequested
    @State private var showsOnboarding = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Destination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol)
                        .tag(destination)
                        .frame(minHeight: stylesheet.sidebar.minimumRowHeight)
                }
            }
            .navigationTitle(String(localized: .patchlightTitle))
            .navigationSplitViewColumnWidth(ideal: stylesheet.sidebar.idealWidth)
        } detail: {
            signedOutDetail
                .navigationTitle((selection ?? .reviewRequested).title)
        }
        .sheet(isPresented: $showsOnboarding) {
            PatchlightOnboardingView()
        }
    }

    private var signedOutDetail: some View {
        ContentUnavailableView {
            Label(String(localized: .knowWhereToLook), systemImage: "scope")
        } description: {
            Text(String(localized: .signedOutDescription))
        } actions: {
            Button(String(localized: .connectGitHub)) {
                showsOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(String(localized: .connectGitHubHint))
        }
        .frame(maxWidth: stylesheet.emptyState.maximumWidth)
        .padding(stylesheet.spacing.xxLarge)
    }
}

#if DEBUG
    extension PatchlightDashboardView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "SignedOut",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPad],
                    colorSchemes: [.light, .dark],
                ),
                settle: .immediate,
            ) {
                PatchlightDashboardView()
                    .patchlightBroadwayRoot()
            }
        }
    }

    #Preview {
        PatchlightDashboardView.snapshotPreviews
    }
#endif
