import PatchlightCore
import SnapshotKit
import SwiftUI

/// Patchlight's signed-out, inbox, repository, and dedicated PR workspace root.
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
    @Environment(\.scenePhase) private var scenePhase
    private let model: PatchlightAppModel
    @State private var selection: Destination? = .reviewRequested
    @State private var showsOnboarding = false
    @State private var showsAISettings = false
    @State private var repositorySearch = ""

    public init(model: PatchlightAppModel) {
        self.model = model
    }

    public init() {
        model = PatchlightAppModel(dependencies: .preview)
    }

    public var body: some View {
        Group {
            switch model.workspaceState {
                case .none:
                    dashboard
                case let .loading(summary):
                    workspaceLoading(summary)
                case let .ready(content):
                    PatchlightWorkspaceView(content: content, model: model)
                case let .failed(summary, message):
                    workspaceFailure(summary, message: message)
            }
        }
        .sheet(isPresented: $showsOnboarding) {
            PatchlightOnboardingView(model: model)
        }
        .sheet(isPresented: $showsAISettings) {
            PatchlightAISettingsView(model: model)
        }
        .task(id: model.dashboardContent?.dashboard.viewer.id) {
            guard model.dashboardContent != nil else { return }
            await model.runVisibleRefreshLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.dashboardContent != nil else { return }
            Task { await model.refreshVisibleContent() }
        }
    }

    private var dashboard: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Destination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol)
                        .badge(badgeCount(for: destination))
                        .tag(destination)
                        .frame(minHeight: stylesheet.sidebar.minimumRowHeight)
                }
            }
            .navigationTitle(String(localized: .patchlightTitle))
            .navigationSplitViewColumnWidth(ideal: stylesheet.sidebar.idealWidth)
        } detail: {
            dashboardDetail
                .navigationTitle((selection ?? .reviewRequested).title)
                .toolbar {
                    if model.dashboardContent != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task { await model.refreshDashboard() }
                            } label: {
                                Label(String(localized: .refresh), systemImage: "arrow.clockwise")
                            }
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            Menu {
                                Button(String(
                                    localized: "settings",
                                    defaultValue: "Settings",
                                )) {
                                    showsAISettings = true
                                }
                                Button(
                                    String(
                                        localized: "signOutGitHub",
                                        defaultValue: "Sign Out of GitHub",
                                    ),
                                    role: .destructive,
                                ) {
                                    Task { await model.signOut() }
                                }
                            } label: {
                                Label(
                                    String(localized: "account", defaultValue: "Account"),
                                    systemImage: "person.crop.circle",
                                )
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var dashboardDetail: some View {
        switch model.accountState {
            case .signedOut, .connecting:
                signedOutDetail
            case let .loading(previous):
                if let previous {
                    dashboardContent(previous, isRefreshing: true)
                } else {
                    ProgressView(String(localized: .loadingGitHub))
                }
            case let .ready(content):
                dashboardContent(content, isRefreshing: false)
            case let .reauthorization(content):
                if let content {
                    dashboardContent(content, isRefreshing: false)
                        .safeAreaInset(edge: .top) { reauthorizationBanner }
                } else {
                    reauthorizationDetail
                }
            case let .failed(previous, message):
                if let previous {
                    dashboardContent(previous, isRefreshing: false)
                        .safeAreaInset(edge: .top) { failureBanner(message) }
                } else {
                    ContentUnavailableView(
                        String(localized: .couldNotLoadGitHub),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message),
                    )
                }
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

    private func dashboardContent(
        _ content: PatchlightDashboardContent,
        isRefreshing: Bool,
    ) -> some View {
        VStack(spacing: 0) {
            if let reason = content.fallbackReason {
                cachedBanner(reason, refreshedAt: content.refreshedAt)
            }
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .accessibilityLabel(String(localized: .refreshing))
            }
            switch selection ?? .reviewRequested {
                case .reviewRequested:
                    pullRequestList(
                        content.dashboard.reviewRequests,
                        emptyTitle: String(localized: .noReviewRequests),
                        emptySymbol: "checkmark.circle",
                    )
                case .ownPullRequests:
                    pullRequestList(
                        content.dashboard.ownPullRequests,
                        emptyTitle: String(localized: .noOpenPullRequests),
                        emptySymbol: "arrow.triangle.pull",
                    )
                case .repositories:
                    repositories(content.dashboard.installations)
            }
        }
    }

    @ViewBuilder
    private func pullRequestList(
        _ pullRequests: [PullRequestSummary],
        emptyTitle: String,
        emptySymbol: String,
    ) -> some View {
        if pullRequests.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
        } else {
            List(pullRequests) { pullRequest in
                Button {
                    Task { await model.openWorkspace(pullRequest) }
                } label: {
                    PullRequestRow(pullRequest: pullRequest)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: .openPullRequestHint))
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func repositories(_ installations: [GitHubInstallationSummary]) -> some View {
        if installations.isEmpty {
            ContentUnavailableView {
                Label(String(localized: .noRepositories), systemImage: "shippingbox")
            } description: {
                Text(String(localized: .installPatchlightDescription))
            } actions: {
                if let url = model.githubAppInstallationURL {
                    Link(String(localized: .installGitHubApp), destination: url)
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            List {
                ForEach(installations) { installation in
                    Section {
                        ForEach(filteredRepositories(in: installation)) { repository in
                            Button {
                                Task { await model.openRepository(repository) }
                            } label: {
                                Label(
                                    repository.coordinates.name,
                                    systemImage: repository.isPrivate ? "lock" : "shippingbox",
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(installation.accountLogin)
                            if installation.teamDiscovery == .permissionWithheld {
                                Image(systemName: "person.2.slash")
                                    .accessibilityLabel(
                                        String(localized: .teamDiscoveryUnavailable),
                                    )
                            }
                        }
                    }
                }
            }
            .searchable(text: $repositorySearch, prompt: String(localized: .searchRepositories))
            .safeAreaInset(edge: .bottom) { repositoryPullRequests }
        }
    }

    @ViewBuilder
    private var repositoryPullRequests: some View {
        switch model.repositoryState {
            case .none:
                EmptyView()
            case let .loading(repository):
                HStack {
                    ProgressView()
                    Text(repository.coordinates.displayName)
                }
                .patchlightStatusBar()
            case let .ready(repository, read):
                VStack(alignment: .leading, spacing: 8) {
                    Text(repository.coordinates.displayName)
                        .font(.headline)
                    if read.value.isEmpty {
                        Text(String(localized: .noOpenPullRequests))
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(read.value) { pullRequest in
                                    Button("#\(pullRequest.id.number) \(pullRequest.title)") {
                                        Task { await model.openWorkspace(pullRequest) }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .patchlightStatusBar()
            case let .failed(repository, message):
                Label(
                    "\(repository.coordinates.displayName): \(message)",
                    systemImage: "exclamationmark.triangle",
                )
                .patchlightStatusBar()
        }
    }

    private var reauthorizationDetail: some View {
        ContentUnavailableView {
            Label(
                String(localized: .reconnectGitHub),
                systemImage: "person.crop.circle.badge.exclamationmark",
            )
        } description: {
            Text(String(localized: .reauthorizationKeepsDrafts))
        } actions: {
            Button(String(localized: .reconnectGitHub)) {
                showsOnboarding = true
                model.startAuthorization()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var reauthorizationBanner: some View {
        HStack {
            Label(String(localized: .reauthorizationKeepsDrafts), systemImage: "key")
            Spacer()
            Button(String(localized: .reconnectGitHub)) {
                showsOnboarding = true
                model.startAuthorization()
            }
        }
        .patchlightBanner(color: .orange)
    }

    private func cachedBanner(_ reason: ReadFallbackReason, refreshedAt: Date) -> some View {
        HStack {
            Label(reason.message, systemImage: "icloud.slash")
            Spacer()
            Text(refreshedAt, style: .relative)
                .foregroundStyle(.secondary)
        }
        .patchlightBanner(color: .orange)
    }

    private func failureBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .frame(maxWidth: .infinity, alignment: .leading)
            .patchlightBanner(color: .red)
    }

    private func workspaceLoading(_ summary: PullRequestSummary) -> some View {
        NavigationStack {
            ProgressView(String(localized: .loadingPullRequest))
                .navigationTitle("#\(summary.id.number) \(summary.title)")
                .toolbar { workspaceCloseButton }
        }
    }

    private func workspaceFailure(_ summary: PullRequestSummary, message: String) -> some View {
        NavigationStack {
            ContentUnavailableView(
                String(localized: .couldNotLoadPullRequest),
                systemImage: "exclamationmark.triangle",
                description: Text(message),
            )
            .navigationTitle("#\(summary.id.number) \(summary.title)")
            .toolbar { workspaceCloseButton }
        }
    }

    @ToolbarContentBuilder
    private var workspaceCloseButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: .backToDashboard)) { model.closeWorkspace() }
        }
    }

    private func filteredRepositories(
        in installation: GitHubInstallationSummary,
    ) -> [RepositorySummary] {
        guard !repositorySearch.isEmpty else { return installation.repositories }
        return installation.repositories.filter {
            $0.coordinates.displayName.localizedCaseInsensitiveContains(repositorySearch)
        }
    }

    private func badgeCount(for destination: Destination) -> Int {
        guard let dashboard = model.dashboardContent?.dashboard else { return 0 }
        return switch destination {
            case .reviewRequested: dashboard.reviewRequests.count
            case .ownPullRequests: dashboard.ownPullRequests.count
            case .repositories: dashboard.installations.reduce(0) { $0 + $1.repositories.count }
        }
    }
}

private struct PullRequestRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pullRequest: PullRequestSummary

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                standardContent
            }
        }
        .contentShape(.rect)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pullRequest.title)
                    .font(.headline)
                Spacer()
                Text("#\(pullRequest.id.number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(pullRequest.repository.displayName)
                Text(pullRequest.authorLogin)
                draftBadge
                requestBadge
                actionabilityBadge
                Spacer()
                Text(pullRequest.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pullRequest.title)
                .font(.headline)
            Text("#\(pullRequest.id.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(pullRequest.repository.displayName)
            Text(pullRequest.authorLogin)
            draftBadge
            requestBadge
            actionabilityBadge
            Text(pullRequest.updatedAt, style: .relative)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var draftBadge: some View {
        if pullRequest.isDraft {
            Text(String(localized: .draft))
                .patchlightBadge(color: .secondary)
        }
    }

    @ViewBuilder
    private var requestBadge: some View {
        switch pullRequest.reviewRequestSource {
            case .direct:
                Text(String(localized: .directRequest))
                    .patchlightBadge(color: .blue)
            case let .team(organization, slug):
                Text("\(organization)/\(slug)")
                    .patchlightBadge(color: .purple)
            case .teamDiscoveryUnavailable:
                Text(String(localized: .teamRequest))
                    .patchlightBadge(color: .orange)
            case .none:
                EmptyView()
        }
    }

    @ViewBuilder
    private var actionabilityBadge: some View {
        switch pullRequest.actionability {
            case .newActivity:
                Text(String(localized: "newActivity", defaultValue: "New activity"))
                    .patchlightBadge(color: .green)
            case .unresolvedThreads:
                Text(String(
                    localized: "unresolvedThreads",
                    defaultValue: "Unresolved threads",
                ))
                .patchlightBadge(color: .orange)
            case .pendingChecks:
                Text(String(localized: "pendingChecks", defaultValue: "Checks pending"))
                    .patchlightBadge(color: .blue)
            case .failedChecks:
                Text(String(localized: "failedChecks", defaultValue: "Checks failed"))
                    .patchlightBadge(color: .red)
            case .changesRequested:
                Text(String(
                    localized: "changesRequested",
                    defaultValue: "Changes requested",
                ))
                .patchlightBadge(color: .orange)
            case .directRequest, .teamRequest, .draft, .waiting:
                EmptyView()
        }
    }
}

extension View {
    fileprivate func patchlightBadge(color: Color) -> some View {
        padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
            .foregroundStyle(color)
    }

    fileprivate func patchlightBanner(color: Color) -> some View {
        padding(.horizontal)
            .padding(.vertical, 10)
            .background(color.opacity(0.12))
    }

    fileprivate func patchlightStatusBar() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }
}

#if DEBUG
    extension PatchlightDashboardView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "SignedOut",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPadFullContent],
                    colorSchemes: [.light, .dark],
                ),
                settle: .immediate,
            ) {
                PatchlightDashboardView(model: PatchlightVisualFixtures.dashboardModel(.signedOut))
                    .patchlightBroadwayRoot()
                    .environment(\.horizontalSizeClass, .regular)
            }
            SnapshotCase(
                name: "Empty",
                configurations: [SnapshotConfiguration(device: .iPadFullContent)],
                settle: .immediate,
            ) {
                PatchlightDashboardView(model: PatchlightVisualFixtures.dashboardModel(
                    .ready(PatchlightVisualFixtures.emptyDashboardContent),
                ))
                .patchlightBroadwayRoot()
                .environment(\.horizontalSizeClass, .regular)
            }
            SnapshotCase(
                name: "Loaded",
                configurations: [
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(colorScheme: .dark, device: .iPadFullContent),
                    SnapshotConfiguration(
                        dynamicType: .accessibility3,
                        device: .iPadFullContent,
                    ),
                    SnapshotConfiguration(contrast: .increased, device: .iPadFullContent),
                    SnapshotConfiguration(
                        layoutDirection: .rightToLeft,
                        device: .iPadFullContent,
                    ),
                ],
                settle: .immediate,
            ) {
                PatchlightDashboardView(model: PatchlightVisualFixtures.dashboardModel(
                    .ready(PatchlightVisualFixtures.dashboardContent),
                ))
                .patchlightBroadwayRoot()
                .environment(\.horizontalSizeClass, .regular)
            }
            SnapshotCase(
                name: "Error",
                configurations: [SnapshotConfiguration(device: .iPadFullContent)],
                settle: .immediate,
            ) {
                PatchlightDashboardView(model: PatchlightVisualFixtures.dashboardModel(
                    .failed(previous: nil, message: "GitHub is temporarily unavailable."),
                ))
                .patchlightBroadwayRoot()
                .environment(\.horizontalSizeClass, .regular)
            }
        }
    }

    #Preview {
        PatchlightDashboardView.snapshotPreviews
    }
#endif
