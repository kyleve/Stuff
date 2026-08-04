import LifecycleKit
import PeriscopeCore
import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
import WhereCore

/// First-run onboarding, run as the launch's opening gate. A short paged
/// intro to the passport concept, then picking the primary regions you spend
/// time in and giving each a look, then the background-location permission
/// request — the natural place to ask for Always, rather than burying it in
/// Settings.
///
/// Nothing exists behind this screen yet: the gate roots the trunk, so the
/// store is unopened and there is no session. Onboarding is what brings the
/// user's world into being — restoring a backup or finishing the flow logs in
/// to the real scope (`WhereModel.resolveScope()`, which performs the app's one
/// store open), commits the picked regions + appearances to it, persists
/// `hasOnboarded`, and resolves the `LifecycleGateHandle` so the launch
/// continues. The steps after the gate then build the session, seed region
/// styling, and pick up whatever permission was granted.
public struct OnboardingView: View {
    // The model is onboarding's whole world: it persists the app-level
    // `hasOnboarded` flag and vends the scope this flow creates. There is no
    // session to hand in — nothing has built one yet.
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet
    private let gate: LifecycleGateHandle

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

    /// What the intro is doing, and how it went — see ``OnboardingIntroState``.
    @State private var intro = OnboardingIntroState()

    /// Whether the backup file picker is up. Separate from the intro's activity
    /// because the system sheet isn't work the intro is doing: it can be
    /// dismissed without starting anything.
    @State private var showImporter = false

    /// How long the demo interstitial stays up at minimum. Seeding a year is
    /// fast enough to flash by, and a screen that appears and vanishes reads
    /// as a glitch rather than as work being done — so the wait is held long
    /// enough to be legible, and no longer.
    private static let demoBuildDisplayTime = Duration.seconds(2)

    private static let logger = WhereLog.session(OnboardingViewLog.self)

    public init(gate: LifecycleGateHandle) {
        self.gate = gate
    }

    private let pages = OnboardingPage.all

    public var body: some View {
        Group {
            switch phase {
                case .intro: introScreen
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
    private var introScreen: some View {
        if intro.isBuildingDemo {
            // The launch splash, captioned for the work: entering demo mode
            // ends in a relaunch through that same splash, so borrowing it
            // here makes the whole entry read as one continuous wait rather
            // than two unrelated screens.
            LaunchSplashView(caption: .work(
                title: String(localized: .demoBuildingTitle),
                subtitle: String(localized: .demoBuildingSubtitle),
            ))
        } else if intro.isRestoringBackup {
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
            failureTitle,
            isPresented: $intro.isShowingFailure,
            presenting: intro.failure,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { failure in
            // Formatted here rather than stored: the state keeps the error
            // itself, so nothing has to decide how to say it before it's shown.
            Text(failure.error.localizedDescription)
        }
    }

    /// The alert's title, which names the task that failed. Empty when
    /// nothing has, in which case the alert isn't presented.
    private var failureTitle: String {
        switch intro.failure?.flow {
            case .restoreBackup: String(localized: .onboardingRestoreErrorTitle)
            case .demo: String(localized: .onboardingDemoErrorTitle)
            case nil: ""
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

            // And anyone can look around first, without handing over a
            // location permission or leaving anything on their device.
            Button(String(localized: .onboardingTryDemo)) { enterDemoMode() }
                .controlSize(.large)
        }
        .disabled(intro.isBuildingDemo)
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

    /// Log in to the user's real world (opening the store, if the restore path
    /// hasn't already), commit the picked regions + appearances, optionally
    /// request location, then persist `hasOnboarded` and resolve the gate so
    /// the launch continues.
    ///
    /// A store that won't open fails the gate rather than stranding the user
    /// on a dead intro: the runner lands on the failure surface, which is
    /// where an unopenable store has always surfaced.
    private func finish(enableLocation: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            let scope: WhereScope
            do {
                scope = try await model.resolveScope()
            } catch {
                Self.logger(attachments: [.error(error, name: "scope-error")]) {
                    .scopeCreationFailed(description: error.localizedDescription)
                }
                gate.fail(error)
                return
            }
            if enableLocation {
                await enableTracking(in: scope)
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
                    try await selection.commit(using: scope)
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

    /// Record the tracking intent and drive the system prompt, so it maps 1:1
    /// to the tap that asked for it. Only these two halves happen here: the
    /// `sync-auth` and `reconcile-tracking` steps run as soon as the gate
    /// resolves, and they are what read the granted authorization back and
    /// actually start GPS.
    private func enableTracking(in scope: WhereScope) async {
        scope.preferences.wantsTracking = true
        do {
            try await scope.services.ingestor.requestPermission()
        } catch {
            // Denied or restricted: nothing to recover here, and re-prompting
            // won't help. Tracking stays intended-but-inactive, and the
            // Location settings screen offers the route to the Settings app.
            Self.logger { .locationPermissionDenied }
        }
    }

    // MARK: - Demo mode

    /// Build a demo world and hand the launch to it: the whole of "entering
    /// demo mode" from the user's side.
    ///
    /// Nothing durable happens here — no store is opened, no permission asked
    /// — so there is nothing to undo if they leave. Resolving the gate is what
    /// lets the launch continue, and it finds the demo scope already active.
    private func enterDemoMode() {
        guard !intro.isBuildingDemo else { return }
        intro.activity = .buildingDemo
        Task {
            do {
                // Seeding and the minimum display run together, so the wait is
                // whichever is longer rather than the sum of the two.
                async let scope = model.makeDemoScope()
                async let settle: Void = Task.sleep(for: Self.demoBuildDisplayTime)
                _ = try await settle
                try await model.activateDemo(scope)
                gate.complete()
            } catch is CancellationError {
                // Nothing to report: the only thing that cancels this is the
                // work itself going away, and there is no user waiting on an
                // answer about it.
                intro.activity = .browsing
            } catch {
                intro.activity = .failed(.init(flow: .demo, error: error))
                Self.logger(attachments: [.error(error, name: "demo-error")]) {
                    .demoBuildFailed(description: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Restore from backup

    private func handleRestoreSelection(_ result: Result<URL, Error>) {
        switch result {
            case let .success(url):
                restore(from: url)
            case let .failure(error):
                intro.activity = .failed(.init(flow: .restoreBackup, error: error))
        }
    }

    /// Import the chosen backup (a fresh install, so `.replace` mirrors the file
    /// exactly), then skip the manual pick/customize steps straight to the
    /// location ask. Restoring is the user committing to their real data, so
    /// this is one of the two places the store gets opened. On failure —
    /// including a store that won't open — surface an alert and stay in the
    /// intro, where they can retry or continue manually.
    private func restore(from url: URL) {
        guard !intro.isRestoringBackup else { return }
        intro.activity = .restoringBackup
        Task {
            do {
                let scope = try await model.resolveScope()
                _ = try await scope.services.backup.importBackup(from: url, strategy: .replace)
                intro.activity = .browsing
                phase = .location
            } catch {
                intro.activity = .failed(.init(flow: .restoreBackup, error: error))
                Self.logger(attachments: [.error(error, name: "restore-error")]) {
                    .backupRestoreFailed(description: error.localizedDescription)
                }
            }
        }
    }
}

/// What the onboarding intro is doing, and how it went.
///
/// One value rather than a pair of "is running" flags beside a loose error:
/// restoring a backup and building a demo each take over the whole screen, so
/// only one can be underway, and a failure always belongs to whichever one
/// produced it. As separate properties, "restoring *and* building" and "failed
/// with no error" were both spellable.
///
/// `@Observable` for the same reason `SaveErrorAlertState` is: the activity
/// stays the single source of truth while `isShowingFailure` gives
/// `.alert(isPresented:)` the binding it wants, without a closure-built
/// `Binding` in the view.
@Observable
final class OnboardingIntroState {
    /// The long task the intro is running, if any.
    enum Activity {
        case browsing
        case restoringBackup
        case buildingDemo
        case failed(Failure)
    }

    /// A task that didn't finish. Holds the error itself rather than a
    /// message, so the view formats it where it presents it — and anything
    /// else that wants to inspect it still can.
    struct Failure {
        /// Which of the intro's two ways forward failed, since they say
        /// different things about it.
        enum Flow {
            case restoreBackup
            case demo
        }

        let flow: Flow
        let error: any Error
    }

    var activity: Activity = .browsing

    var isRestoringBackup: Bool {
        if case .restoringBackup = activity { return true }
        return false
    }

    var isBuildingDemo: Bool {
        if case .buildingDemo = activity { return true }
        return false
    }

    var failure: Failure? {
        if case let .failed(failure) = activity { return failure }
        return nil
    }

    /// Drives the failure alert. Dismissing it returns the intro to browsing,
    /// which is the only way `activity` leaves `.failed`.
    var isShowingFailure: Bool {
        get { failure != nil }
        set { if !newValue { activity = .browsing } }
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
                )
                .environment(PreviewSupport.onboardingModel())
            }
        }
    }

    #Preview {
        OnboardingView.snapshotPreviews
    }
#endif

#if DEBUG
    extension OnboardingView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            OnboardingView.self,
            title: "Onboarding",
            navigationContainer: .none,
        )
    }
#endif
