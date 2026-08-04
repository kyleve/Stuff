import LifecycleKit
import PeriscopeCore
import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
@_spi(Testing) import WhereCore

/// First-run onboarding, run as the launch's opening gate. A short paged
/// intro to the passport concept, then picking the primary regions you spend
/// time in and giving each a look, then confirming whether this device should
/// record automatically. Enabling it requests background-location permission
/// here, rather than burying that decision in Settings.
///
/// No session exists behind this screen: the gate roots the trunk. The final choice may prepare
/// and retain the real store solely to discover synced authority; services and GPS remain dormant.
/// Onboarding is what brings the
/// user's world into being — restoring a backup or finishing the flow logs in
/// to the real scope (`WhereModel.resolveScope()`, which performs the app's one
/// store open), commits the picked regions + appearances to it, persists the
/// confirmed recording choice beside this installation's non-backed-up
/// identity, and resolves the `LifecycleGateHandle` so launch continues. The
/// steps after the gate then build the session, seed region styling, and pick
/// up whatever permission was granted.
public struct OnboardingView: View {
    // The model is onboarding's whole world: it persists the app-level
    // `hasOnboarded` flag and vends the scope this flow creates. There is no
    // session to hand in — nothing has built one yet.
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet
    private let gate: LifecycleGateHandle
    private let installationContext: InstallationRecordingContext

    private var deviceKind: RecordingDeviceKind {
        installationContext.currentDevice.kind
    }

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
    @State private var recordingEnabled: Bool
    @State private var deviceDiscovery: DeviceDiscovery = .idle
    @State private var isFinishing = false
    @State private var restoreSelection = OnboardingRestoreSelection()

    /// What the intro is doing, and how it went — see ``OnboardingIntroState``.
    @State private var intro = OnboardingIntroState()

    /// Whether the backup file picker is up. Separate from the intro's activity
    /// because the system sheet isn't work the intro is doing: it can be
    /// dismissed without starting anything.
    @State private var showImporter = false

    /// A selected backup has no import semantics until the user explicitly
    /// chooses Merge or Replace. Merge is offered first as the safe default.
    @State private var showRestoreStrategyDialog = false

    /// How long the demo interstitial stays up at minimum. Seeding a year is
    /// fast enough to flash by, and a screen that appears and vanishes reads
    /// as a glitch rather than as work being done — so the wait is held long
    /// enough to be legible, and no longer.
    private static let demoBuildDisplayTime = Duration.seconds(2)

    private static let logger = WhereLog.session(OnboardingViewLog.self)

    private enum DeviceDiscovery: Equatable {
        case idle
        case loading
        case ready(RecordingOnboardingRecommendation)
        case failed(String)
    }

    public init(
        gate: LifecycleGateHandle,
        installationContext: InstallationRecordingContext,
    ) {
        self.init(
            gate: gate,
            installationContext: installationContext,
            startsAtRecordingChoice: false,
        )
    }

    /// Internal composition/test initializer. A restored installation whose
    /// backed-up onboarding flag arrived without this non-backed-up context
    /// skips to the device-specific verification page; snapshots use the same
    /// route to capture that page directly.
    init(
        gate: LifecycleGateHandle,
        installationContext: InstallationRecordingContext,
        startsAtRecordingChoice: Bool,
    ) {
        self.gate = gate
        self.installationContext = installationContext
        _phase = State(initialValue: startsAtRecordingChoice ? .location : .intro)
        _recordingEnabled = State(
            initialValue: installationContext.automaticRecordingEnabled
                ?? installationContext.recommendedRecordingEnabled,
        )
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
        .onDisappear(perform: discardPendingRestore)
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
        .confirmationDialog(
            String(localized: .settingsBackupImportStrategyTitle),
            isPresented: $showRestoreStrategyDialog,
            titleVisibility: .visible,
            presenting: restoreSelection.selectedURL,
        ) { _ in
            Button(String(localized: .onboardingRestoreMergeRecommended)) {
                chooseRestoreStrategy(OnboardingRestoreSelection.recommendedStrategy)
            }
            Button(String(localized: .settingsBackupReplace), role: .destructive) {
                chooseRestoreStrategy(.replace)
            }
            Button(String(localized: .settingsDataCancel), role: .cancel) {
                discardPendingRestore()
            }
        } message: { _ in
            Text(String(localized: .settingsBackupImportStrategyMessage))
        }
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
        intro.failure?.flow.title ?? ""
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
                    discardPendingRestore()
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: stylesheet.spacing.xxxLarge) {
                    Spacer(minLength: 0)
                    Image(systemName: deviceKind.systemImage)
                        .font(stylesheet.typography.onboardingIcon)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(spacing: stylesheet.spacing.large) {
                        Text(recordingTitle)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(String(localized: .onboardingRecordingDescription))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 0)

                    VStack(spacing: stylesheet.spacing.large) {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            switch deviceDiscovery {
                                case .idle, .loading:
                                    ProgressView(String(localized: .onboardingRecordingChecking))
                                case let .ready(recommendation):
                                    if recommendation.recentRecordingDevice != nil {
                                        Label(
                                            String(localized: .onboardingRecordingRecent),
                                            systemImage: "iphone.radiowaves.left.and.right",
                                        )
                                    }
                                case let .failed(description):
                                    Label(description, systemImage: "icloud.slash")
                                        .foregroundStyle(.secondary)
                            }
                            Toggle(
                                String(localized: .settingsDevicesAutomaticRecording),
                                isOn: $recordingEnabled,
                            )
                            Text(recordingRecommendation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            // Request Always-location only after the user confirms an
                            // enabled choice; the launch's reconcile step picks up
                            // whatever the system grants.
                            finish(enableLocation: recordingEnabled)
                        } label: {
                            Text(String(localized: .onboardingContinue))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .disabled(isFinishing || deviceDiscovery == .loading)
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await discoverRecordingDevices() }
    }

    private var recordingTitle: LocalizedStringResource {
        switch deviceKind {
            case .phone: .onboardingRecordingPhoneTitle
            case .tablet: .onboardingRecordingTabletTitle
            case .other: .onboardingRecordingOtherTitle
        }
    }

    private var recordingRecommendation: LocalizedStringResource {
        let recommendsEnabled = if case let .ready(recommendation) = deviceDiscovery {
            recommendation.isEnabled
        } else {
            installationContext.recommendedRecordingEnabled
        }
        if recommendsEnabled {
            return .onboardingRecordingRecommendationOn
        } else {
            return .onboardingRecordingRecommendationOff
        }
    }

    /// Persist this installation's choice first, then log in to the user's real
    /// world, optionally restore a selected backup, commit manual region picks,
    /// request location when enabled, and resolve the gate.
    ///
    /// A store that won't open fails the gate rather than stranding the user
    /// on a dead intro: the runner lands on the failure surface, which is
    /// where an unopenable store has always surfaced.
    private func finish(enableLocation: Bool) {
        guard !isFinishing else { return }
        let readyImport = restoreSelection.readyImport
        if restoreSelection.selectedURL != nil {
            guard readyImport != nil else {
                assertionFailure("An onboarding restore must have an explicit import strategy.")
                discardPendingRestore()
                return
            }
            // Opening the real CloudKit-backed scope is part of restore work and
            // can be slow. Move to the blocking progress surface before that
            // first await rather than leaving a disabled Continue button behind.
            intro.activity = .restoringBackup
            phase = .intro
        }
        isFinishing = true
        Task {
            do {
                let context = try model.confirmInitialRecordingChoice(isEnabled: enableLocation)
                guard context.automaticRecordingEnabled != nil else {
                    preconditionFailure("A confirmed installation context must carry its choice.")
                }
            } catch {
                Self.logger(attachments: [.error(error, name: "context-error")]) {
                    .installationContextWriteFailed(description: error.localizedDescription)
                }
                gate.fail(error)
                return
            }

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

            if let readyImport {
                do {
                    let summary = try await scope.services.backup.importBackup(
                        from: readyImport.url,
                        strategy: readyImport.strategy,
                        purpose: .onboarding,
                    )
                    restoreSelection.markCommitted(summary)
                    // Persist the irreversible boundary immediately. If the process stops before
                    // device setup finishes, the next launch continues with the imported world
                    // instead of offering to apply the same archive again.
                    model.completeOnboarding()
                    do {
                        try await scope.services.backup.acknowledgeOnboardingImport()
                    } catch {
                        gate.fail(OnboardingCommittedImportSetupError(
                            summary: summary,
                            underlying: error,
                        ))
                        return
                    }
                } catch let error as BackupCoordinator.CommittedImportCleanupError {
                    restoreSelection.markCommitted(error.summary)
                    // The archive is already committed. Complete onboarding and
                    // fail the gate into the terminal, relaunch-required partial-
                    // success surface; returning to the Restore button would lie
                    // about rollback and could apply the archive twice.
                    model.completeOnboarding()
                    do {
                        try await scope.services.backup.acknowledgeOnboardingImport()
                    } catch let acknowledgementError {
                        gate.fail(OnboardingCommittedImportSetupError(
                            summary: error.summary,
                            underlying: acknowledgementError,
                        ))
                        return
                    }
                    Self.logger(attachments: [.error(error.underlying, name: "cleanup-error")]) {
                        .backupRestoreCleanupFailed(
                            description: error.underlying.localizedDescription,
                        )
                    }
                    gate.fail(error)
                    return
                } catch let error as BackupCoordinator.CommittedImportSupersededError {
                    restoreSelection.markCommitted(error.summary)
                    model.completeOnboarding()
                    do {
                        try await scope.services.backup.acknowledgeOnboardingImport()
                    } catch let acknowledgementError {
                        gate.fail(OnboardingCommittedImportSetupError(
                            summary: error.summary,
                            underlying: acknowledgementError,
                        ))
                        return
                    }
                    gate.fail(error)
                    return
                } catch let error as BackupCoordinator.ImportRecoveryResolutionError {
                    // The durable prepared marker remains authoritative, but receipt resolution
                    // failed. Never return to an importer that could apply the archive twice.
                    gate.fail(error)
                    return
                } catch {
                    restoreSelection.discardUncommittedSelection()
                    // Drop the failed scope before retrying. The immutable first choice remains
                    // fixed; the retry creates a fresh scope over that same installation context.
                    await model.endSession()
                    intro.activity = .failed(.init(flow: .restoreBackup, error: error))
                    phase = .intro
                    isFinishing = false
                    Self.logger(attachments: [.error(error, name: "restore-error")]) {
                        .backupRestoreFailed(description: error.localizedDescription)
                    }
                    return
                }
            }

            // Apply the choice persisted before this scope opened, then start physical recording
            // only after the rest of onboarding or restore work has succeeded.
            do {
                let authorization = await scope.services.ingestor.authorizationStatus()
                try await scope.services.recording.registerForOnboarding(
                    desiredEnabled: enableLocation,
                    authorization: authorization,
                )
            } catch {
                Self.logger(attachments: [.error(error, name: "recording-configuration-error")]) {
                    .recordingConfigurationFailed(description: error.localizedDescription)
                }
                if let summary = restoreSelection.committedSummary {
                    // The import cannot roll back with this later setup failure. Preserve its
                    // summary in the terminal result. Onboarding completed at the commit
                    // boundary, so a cold retry registers this installation without reapplying
                    // the archive.
                    gate.fail(OnboardingCommittedImportSetupError(
                        summary: summary,
                        underlying: error,
                    ))
                } else {
                    gate.fail(error)
                }
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
            if !model.hasOnboarded {
                model.completeOnboarding()
            }
            gate.complete()
        }
    }

    private func discoverRecordingDevices() async {
        guard deviceDiscovery == .idle else { return }
        deviceDiscovery = .loading
        do {
            let recommendation = try await model.discoverRecordingRecommendation(
                for: installationContext,
            )
            deviceDiscovery = .ready(recommendation)
            if installationContext.automaticRecordingEnabled == nil {
                recordingEnabled = recommendation.isEnabled
            }
        } catch {
            deviceDiscovery = .failed(error.localizedDescription)
        }
    }

    /// Drive the system prompt for the recording choice already persisted in
    /// the installation context, so the prompt maps 1:1 to the tap that asked
    /// for it. The `sync-auth` and `reconcile-tracking` steps run as soon as the
    /// gate resolves; they read the granted authorization back and start GPS.
    private func enableTracking(in scope: WhereScope) async {
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
                restoreSelection.select(
                    url: url,
                    hasScopedAccess: url.startAccessingSecurityScopedResource(),
                )
                showRestoreStrategyDialog = true
            case let .failure(error):
                discardPendingRestore()
                intro.activity = .failed(.init(flow: .restoreBackup, error: error))
        }
    }

    private func chooseRestoreStrategy(_ strategy: BackupCoordinator.ImportStrategy) {
        guard restoreSelection.selectedURL != nil else {
            assertionFailure("A restore strategy was chosen without a selected backup.")
            return
        }
        restoreSelection.choose(strategy)
        phase = .location
    }

    /// Keep the file importer's security-scoped URL available while the user
    /// verifies this installation's recording choice, then balance access as
    /// soon as the import finishes or onboarding leaves the hierarchy.
    private func discardPendingRestore() {
        showRestoreStrategyDialog = false
        restoreSelection.discardUncommittedSelection()
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
        enum Flow: Equatable {
            case restoreBackup
            case demo

            var title: String {
                switch self {
                    case .restoreBackup: String(localized: .onboardingRestoreErrorTitle)
                    case .demo: String(localized: .onboardingDemoErrorTitle)
                }
            }
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
            [
                whereSnapshot(name: "Default", configurations: .screenDefaults) {
                    // `onboardingModel()` (not `loadedModel()`) so `hasOnboarded`
                    // is false and the capture lands on the intro phase.
                    OnboardingView(
                        gate: LifecycleGateHandle(
                            id: LaunchStepID.onboarding,
                            reason: .userForeground,
                        ),
                        installationContext: .testing,
                    )
                    .environment(PreviewSupport.onboardingModel())
                },
                whereSnapshot(
                    name: "PhoneRecordingChoice",
                    configurations: SnapshotConfiguration.combinations(devices: [.iPhone]) + [
                        SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhone),
                    ],
                ) {
                    OnboardingView(
                        gate: LifecycleGateHandle(
                            id: LaunchStepID.onboarding,
                            reason: .userForeground,
                        ),
                        installationContext: .testing,
                        startsAtRecordingChoice: true,
                    )
                    .environment(PreviewSupport.onboardingModel())
                },
                whereSnapshot(
                    name: "TabletRecordingChoice",
                    configurations: SnapshotConfiguration.combinations(devices: [.iPad]),
                ) {
                    OnboardingView(
                        gate: LifecycleGateHandle(
                            id: LaunchStepID.onboarding,
                            reason: .userForeground,
                        ),
                        installationContext: InstallationRecordingContext(
                            currentDevice: CurrentRecordingDevice(
                                id: RecordingDeviceID(
                                    rawValue: UUID(
                                        uuidString: "00000000-0000-0000-0000-000000000003",
                                    )!,
                                ),
                                systemName: "iPad",
                                kind: .tablet,
                            ),
                            registeredAt: InstallationRecordingContext.testing.registeredAt,
                            recordingChoice: .unconfirmed,
                            isRejoining: false,
                        ),
                        startsAtRecordingChoice: true,
                    )
                    .environment(PreviewSupport.onboardingModel())
                },
            ]
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
