import LifecycleKit
import PeriscopeCore
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
/// resolves the `LifecycleGateHandle` so the launch continues; the following
/// authorization-sync step then seeds region styling and picks up whatever
/// permission was granted.
public struct OnboardingView: View {
    // Onboarding straddles both: it persists the app-level `hasOnboarded` flag
    // (model) and kicks off background tracking + the region commit through
    // the session — handed in by the gate registration (the gate passes the
    // trunk's session through), not trusted to be in the environment.
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet
    private let gate: LifecycleGateHandle
    private let session: WhereSession

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

    private static let logger = WhereLog.session(OnboardingViewLog.self)

    public init(gate: LifecycleGateHandle, session: WhereSession) {
        self.gate = gate
        self.session = session
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
        // Log View Mode: reveal an inspect badge for onboarding events (region
        // commit / backup restore). A no-op in release.
        .debugLogInspectable(WhereLog.session(OnboardingViewLog.self))
    }

    // MARK: - Intro

    @ViewBuilder
    private var intro: some View {
        if isRestoring {
            // A backup restore is a whole-screen blocking wait, so show the
            // shared app-icon loading treatment (as first-load / scan / summary
            // do) rather than an inline spinner.
            AppIconLoadingView(caption: String(localized: .onboardingRestoring))
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
            String(localized: .onboardingRestoreErrorTitle),
            isPresented: $showRestoreError,
            presenting: restoreError,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
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
                Text(String(localized: .onboardingContinue))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Returning users can skip the manual setup by restoring a backup;
            // the restore's progress replaces the intro with the loading view.
            Button(String(localized: .onboardingRestoreBackup)) { showImporter = true }
                .controlSize(.large)
        }
    }

    // MARK: - Pick regions

    private var pickRegions: some View {
        NavigationStack {
            RegionPickerView(model: selection)
                .navigationTitle(String(localized: .onboardingRegionsTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .onboardingNext)) { phase = .customize }
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
                Text(String(localized: .onboardingLocationTitle))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: .onboardingLocationDescription))
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
                    Text(String(localized: .onboardingEnableLocation))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(String(localized: .onboardingNotNow)) {
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
                    Self.logger(attachments: [.error(error, name: "commit-error")]) {
                        .regionCommitFailed(description: error.localizedDescription)
                    }
                }
            }
            model.completeOnboarding()
            gate.complete()
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
                Self.logger(attachments: [.error(error, name: "restore-error")]) {
                    .backupRestoreFailed(description: error.localizedDescription)
                }
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
            title: String(localized: .onboardingWelcomeTitle),
            description: String(localized: .onboardingWelcomeDescription),
        ),
        OnboardingPage(
            id: "automatic",
            symbol: "location.fill.viewfinder",
            title: String(localized: .onboardingAutomaticTitle),
            description: String(localized: .onboardingAutomaticDescription),
        ),
        OnboardingPage(
            id: "privacy",
            symbol: "lock.shield.fill",
            title: String(localized: .onboardingPrivacyTitle),
            description: String(localized: .onboardingPrivacyDescription),
        ),
    ]
}

#if DEBUG
    extension OnboardingView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                // `onboardingModel()` (not `loadedModel()`) so `hasOnboarded` is
                // false and the capture lands on the intro phase.
                OnboardingView(
                    gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
                    session: PreviewSupport.loadedSession(),
                )
                .environment(PreviewSupport.onboardingModel())
            }
        }
    }

    #Preview {
        OnboardingView.snapshotPreviews
    }
#endif
