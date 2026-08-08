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
    @State private var flow: OnboardingFlowModel

    private var deviceKind: RecordingDeviceKind {
        flow.installationContext.currentDevice.kind
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
        _flow = State(initialValue: OnboardingFlowModel(
            gate: gate,
            installationContext: installationContext,
            startsAtRecordingChoice: startsAtRecordingChoice,
        ))
    }

    private let pages = OnboardingPage.all

    public var body: some View {
        Group {
            switch flow.phase {
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
        .animation(stylesheet.motion.reducedReveal, value: flow.phase)
        .onDisappear { flow.discardPendingRestore() }
        // Log View Mode: reveal an inspect badge for onboarding events (region
        // commit / backup restore). A no-op in release.
        .debugLogInspectable(WhereLog.session(OnboardingViewLog.self))
    }

    // MARK: - Intro

    @ViewBuilder
    private var introScreen: some View {
        if flow.intro.isBuildingDemo {
            // The launch splash, captioned for the work: entering demo mode
            // ends in a relaunch through that same splash, so borrowing it
            // here makes the whole entry read as one continuous wait rather
            // than two unrelated screens.
            LaunchSplashView(caption: .work(
                title: String(localized: .demoBuildingTitle),
                subtitle: String(localized: .demoBuildingSubtitle),
            ))
        } else if flow.intro.isRestoringBackup {
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
            TabView(selection: $flow.page) {
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
            isPresented: $flow.showImporter,
            allowedContentTypes: [.zip],
            onCompletion: flow.handleRestoreSelection,
        )
        .confirmationDialog(
            String(localized: .settingsBackupImportStrategyTitle),
            isPresented: $flow.showRestoreStrategyDialog,
            titleVisibility: .visible,
            presenting: flow.restoreSelection.selectedURL,
        ) { _ in
            Button(String(localized: .onboardingRestoreMergeRecommended)) {
                flow.chooseRestoreStrategy(OnboardingRestoreSelection.recommendedStrategy)
            }
            Button(String(localized: .settingsBackupReplace), role: .destructive) {
                flow.chooseRestoreStrategy(.replace)
            }
            Button(String(localized: .settingsDataCancel), role: .cancel) {
                flow.discardPendingRestore()
            }
        } message: { _ in
            Text(String(localized: .settingsBackupImportStrategyMessage))
        }
        .alert(
            flow.failureTitle,
            isPresented: $flow.intro.isShowingFailure,
            presenting: flow.intro.failure,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { failure in
            // Formatted here rather than stored: the state keeps the error
            // itself, so nothing has to decide how to say it before it's shown.
            Text(failure.error.localizedDescription)
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
                withAnimation { flow.advanceIntro(pageCount: pages.count) }
            } label: {
                Text(String(localized: .onboardingContinue))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Returning users can skip the manual setup by restoring a backup;
            // the restore's progress replaces the intro with the loading view.
            Button(String(localized: .onboardingRestoreBackup)) { flow.showImporter = true }
                .controlSize(.large)

            // And anyone can look around first, without handing over a
            // location permission or leaving anything on their device.
            Button(String(localized: .onboardingTryDemo)) { flow.enterDemoMode(using: model) }
                .controlSize(.large)
        }
        .disabled(flow.intro.isBuildingDemo)
    }

    // MARK: - Pick regions

    private var pickRegions: some View {
        NavigationStack {
            RegionPickerView(model: flow.selection)
                .navigationTitle(String(localized: .onboardingRegionsTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .onboardingNext)) { flow.phase = .customize }
                            .disabled(!flow.selection.hasSelection)
                    }
                }
        }
    }

    // MARK: - Customize

    private var customize: some View {
        NavigationStack {
            RegionCustomizeView(
                model: flow.selection,
                onBack: { flow.phase = .pickRegions },
                onFinish: { flow.phase = .location },
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
                            switch flow.deviceDiscovery {
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
                                isOn: $flow.recordingEnabled,
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
                            flow.finish(using: model)
                        } label: {
                            Text(String(localized: .onboardingContinue))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .disabled(flow.isFinishing || flow.deviceDiscovery == .loading)
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await flow.discoverRecordingDevices(using: model) }
    }

    private var recordingTitle: LocalizedStringResource {
        switch deviceKind {
            case .phone: .onboardingRecordingPhoneTitle
            case .tablet: .onboardingRecordingTabletTitle
            case .computer, .watch, .other: .onboardingRecordingOtherTitle
        }
    }

    private var recordingRecommendation: LocalizedStringResource {
        let recommendsEnabled = if case let .ready(recommendation) = flow.deviceDiscovery {
            recommendation.isEnabled
        } else {
            flow.installationContext.recommendedRecordingEnabled
        }
        if recommendsEnabled {
            return .onboardingRecordingRecommendationOn
        } else {
            return .onboardingRecordingRecommendationOff
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
                    // is false and the capture lands on the intro flow.phase.
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
