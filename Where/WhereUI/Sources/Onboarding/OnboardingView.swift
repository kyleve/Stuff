import LifecycleKit
import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// First-run onboarding, run as one interactive launch step. A short paged
/// intro to the passport concept, then picking the primary regions you spend
/// time in and giving each a look, then the background-location permission
/// request — the natural place to ask for Always, rather than burying it in
/// Settings.
///
/// When the user finishes it commits the picked regions + appearances to the
/// store (which becomes the tracked-region set), persists `hasOnboarded`, and
/// resolves the `LifecycleStepUIBridge` so the launch continues; the following
/// authorization-sync step then seeds region styling and picks up whatever
/// permission was granted.
public struct OnboardingView: View {
    // Onboarding straddles both: it persists the app-level `hasOnboarded` flag
    // (model) and kicks off background tracking + the region commit through the
    // session, which the `open-store` step has already built by the time this
    // step runs.
    @Environment(WhereModel.self) private var model
    @Environment(WhereSession.self) private var session
    @Environment(\.stylesheet) private var stylesheet
    private let bridge: LifecycleStepUIBridge

    /// The ordered onboarding phases. An explicit state machine (rather than
    /// loose flags) so only one screen is ever showing and the transitions are
    /// obvious.
    private enum Phase: Hashable {
        case intro
        case pickRegions
        case customize
        case location
    }

    @State private var phase: Phase = .intro
    @State private var page = 0
    @State private var selection = PrimaryRegionSelectionModel()
    @State private var isFinishing = false

    // Restore-from-backup: the escape hatch that skips manual region setup.
    @State private var showImporter = false
    @State private var isRestoring = false
    @State private var showRestoreError = false
    @State private var restoreError: String?

    private static let logger = WhereLog.channel(.model)

    public init(bridge: LifecycleStepUIBridge) {
        self.bridge = bridge
    }

    private let pages = OnboardingPage.all

    public var body: some View {
        Group {
            switch phase {
                case .intro: intro
                case .pickRegions: pickRegions
                case .customize: customize
                case .location: location
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    stylesheet.palette.onboarding.backgroundTop,
                    stylesheet.palette.onboarding.backgroundBottom,
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea(),
        )
        .animation(stylesheet.motion.reducedReveal, value: phase)
    }

    // MARK: - Intro

    @ViewBuilder
    private var intro: some View {
        if isRestoring {
            // A backup restore is a whole-screen blocking wait, so show the
            // shared app-icon loading treatment (as first-load / scan / summary
            // do) rather than an inline spinner.
            AppIconLoadingView(caption: Strings.onboardingRestoring)
        } else {
            introPages
        }
    }

    private var introPages: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                        .padding(.horizontal, stylesheet.spacing.xxxLarge)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            introFooter
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip],
            onCompletion: handleRestoreSelection,
        )
        .alert(
            Strings.onboardingRestoreErrorTitle,
            isPresented: $showRestoreError,
            presenting: restoreError,
        ) { _ in
            Button(Strings.commonOK, role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: page.symbol)
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.large) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
    }

    private var introFooter: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    phase = .pickRegions
                }
            } label: {
                Text(Strings.onboardingContinue)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Returning users can skip the manual setup by restoring a backup;
            // the restore's progress replaces the intro with the loading view.
            Button(Strings.onboardingRestoreBackup) { showImporter = true }
                .controlSize(.large)
        }
    }

    // MARK: - Pick regions

    private var pickRegions: some View {
        NavigationStack {
            RegionPickerView(model: selection)
                .navigationTitle(Strings.onboardingRegionsTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.onboardingNext) { phase = .customize }
                            .disabled(!selection.hasSelection)
                    }
                }
        }
    }

    // MARK: - Customize

    private var customize: some View {
        NavigationStack {
            RegionCustomizeView(
                model: selection,
                onBack: { phase = .pickRegions },
                onFinish: { phase = .location },
            )
        }
    }

    // MARK: - Location

    private var location: some View {
        VStack(spacing: stylesheet.spacing.xxxLarge) {
            Spacer(minLength: 0)
            Image(systemName: "location.fill.viewfinder")
                .font(stylesheet.typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(spacing: stylesheet.spacing.large) {
                Text(Strings.onboardingLocationTitle)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(Strings.onboardingLocationDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)

            VStack(spacing: stylesheet.spacing.large) {
                Button {
                    // Request Always-location right here so the system prompt
                    // maps 1:1 to the tap; the launch's tracking-reconcile step
                    // picks up whatever was granted.
                    finish(enableLocation: true)
                } label: {
                    Text(Strings.onboardingEnableLocation)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(Strings.onboardingNotNow) {
                    finish(enableLocation: false)
                }
                .controlSize(.large)
            }
            .disabled(isFinishing)
        }
        .padding(.horizontal, stylesheet.spacing.xxxLarge)
        .padding(.bottom, stylesheet.spacing.xxxLarge)
    }

    /// Commit the picked regions + appearances, optionally request location,
    /// then persist `hasOnboarded` and resolve the step so the launch continues.
    private func finish(enableLocation: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            if enableLocation {
                await session.startTracking()
            }
            // Only commit when the user actually picked regions in the manual
            // flow. The restore path reaches here with an empty selection (it
            // jumps intro → location), and committing empty would replace — i.e.
            // wipe — the regions the restore just wrote. Guarding on `hasSelection`
            // (rather than a "did restore" flag) makes that impossible: the
            // manual flow can't reach `finish` empty (its Next is gated on a
            // selection), so a non-empty selection is exactly "the user picked".
            if selection.hasSelection {
                do {
                    try await selection.commit(using: session)
                } catch {
                    // Don't strand the user in onboarding on a write failure —
                    // log it and continue; they can re-pick in Settings.
                    Self.logger.warning("Failed to commit onboarding region picks")
                }
            }
            model.completeOnboarding()
            bridge.complete()
        }
    }

    // MARK: - Restore from backup

    private func handleRestoreSelection(_ result: Result<URL, Error>) {
        switch result {
            case let .success(url):
                restore(from: url)
            case let .failure(error):
                restoreError = error.localizedDescription
                showRestoreError = true
        }
    }

    /// Import the chosen backup (a fresh install, so `.replace` mirrors the file
    /// exactly), then skip the manual pick/customize steps straight to the
    /// location ask. On failure, surface an alert and stay in the intro.
    private func restore(from url: URL) {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            do {
                _ = try await session.services.backup.importBackup(from: url, strategy: .replace)
                isRestoring = false
                phase = .location
            } catch {
                isRestoring = false
                restoreError = error.localizedDescription
                showRestoreError = true
                Self.logger.warning("Onboarding backup restore failed")
            }
        }
    }
}

/// One page of the onboarding intro. A plain value (not a view) so the page
/// list reads declaratively and stays easy to reorder.
struct OnboardingPage: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let description: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            symbol: "globe.americas.fill",
            title: Strings.onboardingWelcomeTitle,
            description: Strings.onboardingWelcomeDescription,
        ),
        OnboardingPage(
            id: "automatic",
            symbol: "location.fill.viewfinder",
            title: Strings.onboardingAutomaticTitle,
            description: Strings.onboardingAutomaticDescription,
        ),
        OnboardingPage(
            id: "privacy",
            symbol: "lock.shield.fill",
            title: Strings.onboardingPrivacyTitle,
            description: Strings.onboardingPrivacyDescription,
        ),
    ]
}

#if DEBUG
    extension OnboardingView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                let model = PreviewSupport.onboardingModel()
                OnboardingView(bridge: LifecycleStepUIBridge(reason: .userForeground))
                    .environment(model)
                    .environment(model.session)
            }
        }
    }

    #Preview {
        OnboardingView.snapshotPreviews
    }
#endif
