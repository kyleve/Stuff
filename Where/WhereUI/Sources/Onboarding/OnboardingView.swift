import LifecycleKit
import PeriscopeCore
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import UniformTypeIdentifiers
@_spi(Testing) import WhereCore

/// First-run onboarding, run as the launch's user-facing gate. A short paged
/// intro to the passport concept, then picking the primary regions you spend
/// time in and giving each a look, then confirming whether this device should
/// record automatically. Enabling it requests background-location permission
/// here, rather than burying that decision in Settings.
///
/// No session exists behind this screen: the gate precedes every step that builds
/// the user's world. The final choice may prepare and retain the real store solely
/// to discover synced authority; services and GPS remain dormant.
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

    public init(
        gate: LifecycleGateHandle,
        installationContext: InstallationRecordingContext,
    ) {
        self.init(
            gate: gate,
            installationContext: installationContext,
            startsAtRecordingChoice: false,
            initialTheme: .standard,
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
        initialTheme: WhereTheme = .standard,
    ) {
        _flow = State(initialValue: OnboardingFlowModel(
            gate: gate,
            installationContext: installationContext,
            startsAtRecordingChoice: startsAtRecordingChoice,
            initialTheme: initialTheme,
        ))
    }

    public var body: some View {
        Group {
            switch flow.phase {
                case .intro: OnboardingIntroScreen(flow: flow)
                case .theme:
                    OnboardingThemeSelectionView(
                        selection: flow.theme,
                        onSelect: { flow.selectTheme($0, using: model) },
                        onContinue: flow.continueAfterThemeSelection,
                    )
                case .pickRegions: OnboardingRegionSelection(flow: flow)
                case .customize: OnboardingRegionCustomization(flow: flow)
                case .location: OnboardingRecordingChoice(flow: flow)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingBackground())
        .animation(stylesheet.motion.reducedReveal, value: flow.phase)
        .onDisappear { flow.discardPendingRestore() }
        // Log View Mode: reveal an inspect badge for onboarding events (region
        // commit / backup restore). A no-op in release.
        .debugLogInspectable(WhereLog.session(OnboardingViewLog.self))
    }
}

private struct OnboardingIntroScreen: View {
    let flow: OnboardingFlowModel

    var body: some View {
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
            OnboardingIntroPages(flow: flow)
        }
    }
}

private struct OnboardingRegionSelection: View {
    let flow: OnboardingFlowModel

    var body: some View {
        NavigationStack {
            RegionPickerView(draft: flow.selection)
                .navigationTitle(String(localized: .onboardingRegionsTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .onboardingNext)) { flow.phase = .customize }
                            .disabled(!flow.selection.hasSelection)
                    }
                }
        }
    }
}

private struct OnboardingRegionCustomization: View {
    let flow: OnboardingFlowModel

    var body: some View {
        NavigationStack {
            RegionCustomizeView(
                draft: flow.selection,
                onBack: { flow.phase = .pickRegions },
                onFinish: { flow.phase = .location },
            )
        }
    }
}

struct OnboardingBackground: View {
    @Environment(\.stylesheet.palette.onboarding) private var palette

    var body: some View {
        LinearGradient(
            colors: [
                palette.backgroundTop,
                palette.backgroundBottom,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
        .ignoresSafeArea()
    }
}

struct OnboardingHeading: View {
    let title: Text
    let description: Text
    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        VStack(spacing: spacing.large) {
            title
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            description
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct OnboardingContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(localized: .onboardingContinue))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
        if case .restoringBackup = activity {
            return true
        }
        return false
    }

    var isBuildingDemo: Bool {
        if case .buildingDemo = activity {
            return true
        }
        return false
    }

    var failure: Failure? {
        if case let .failed(failure) = activity {
            return failure
        }
        return nil
    }

    /// Drives the failure alert. Dismissing it returns the intro to browsing,
    /// which is the only way `activity` leaves `.failed`.
    var isShowingFailure: Bool {
        get { failure != nil }
        set {
            if !newValue {
                activity = .browsing
            }
        }
    }
}

/// One page of the onboarding intro. A plain value (not a view) so the page
/// list reads declaratively and stays easy to reorder.
struct OnboardingPage: Identifiable {
    let id: String
    let symbol: SFSymbol
    let title: String
    let description: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            symbol: .globeAmericasFill,
            title: String(localized: .onboardingWelcomeTitle),
            description: String(localized: .onboardingWelcomeDescription),
        ),
        OnboardingPage(
            id: "automatic",
            symbol: .locationFillViewfinder,
            title: String(localized: .onboardingAutomaticTitle),
            description: String(localized: .onboardingAutomaticDescription),
        ),
        OnboardingPage(
            id: "privacy",
            symbol: .lockShieldFill,
            title: String(localized: .onboardingPrivacyTitle),
            description: String(localized: .onboardingPrivacyDescription),
        ),
    ]
}

#if DEBUG
    extension OnboardingView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(name: "Default", configurations: .phoneLightDark + [
                    SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhone),
                    SnapshotConfiguration(contrast: .increased, device: .iPhone),
                    SnapshotConfiguration(device: .iPhone, snapshotType: .accessibility),
                    SnapshotConfiguration(device: .iPad),
                    SnapshotConfiguration(device: .iPad, snapshotType: .accessibility),
                    // The wider text column has its own pager/footer fit at AX5.
                    SnapshotConfiguration(dynamicType: .accessibility5, device: .iPad),
                ]) {
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
                    configurations: SnapshotConfiguration
                        .combinations(devices: [.iPhoneFullContent]) + [
                            SnapshotConfiguration(
                                dynamicType: .accessibility5,
                                device: .iPhoneFullContent,
                            ),
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
                    configurations: SnapshotConfiguration.combinations(devices: [.iPadFullContent]),
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
