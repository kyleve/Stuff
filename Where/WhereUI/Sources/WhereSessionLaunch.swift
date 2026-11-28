import LifecycleKit
import LifecycleKitUI
import SwiftUI
import WhereCore

struct WhereSessionLaunch: View {
    let model: WhereModel
    let launcher: LifecycleRunner<WhereSession>
    let style: WhereStylesheet.LaunchStyle
    let isPresentationVisible: Bool

    var body: some View {
        LifecycleContainer(
            launcher,
            transition: style.reveal.transition,
            animation: style.revealAnimation,
            minimumSplashDuration: style.minimumSplashDuration,
            isPresentationVisible: isPresentationVisible,
            splash: { _ in
                WhereSessionLaunchSplash(isBuildingDemo: model.isBuildingLaunchDemo)
            },
            failure: { WhereLifecycleFailureView(failure: $0) },
            gates: {
                // The gate precedes every world-building step, so there is
                // no session (and no open store) behind it yet — onboarding
                // builds the scope it commits regions with, through the model.
                // The monitor completes this gate after admission. The outer
                // branch owns lockout UI; keep a registration while it drains.
                GateView(for: CompatibilityGate.self) { _, _ in
                    LaunchSplashView()
                }
                GateView(for: OnboardingGate.self) { handle, _ in
                    OnboardingView(
                        gate: handle,
                        installationContext: model.installationRecordingContext,
                        startsAtRecordingChoice: model.hasOnboarded,
                        initialTheme: model.theme,
                    )
                }
            },
        ) { session in
            WhereSessionDestination(model: model, session: session)
        }
    }
}

private struct WhereSessionLaunchSplash: View {
    let isBuildingDemo: Bool

    var body: some View {
        if isBuildingDemo {
            LaunchSplashView(caption: .work(
                title: String(localized: .demoBuildingTitle),
                subtitle: String(localized: .demoBuildingSubtitle),
            ))
        } else {
            LaunchSplashView()
        }
    }
}

private struct WhereSessionDestination: View {
    let model: WhereModel
    let session: WhereSession

    var body: some View {
        // `.ready` carries the session the launch produced — the app
        // surface cannot render without it. `MainTabs` owns the
        // scene-scoped `YearReportModel` and gets a fresh one whenever
        // a reset rebuilds the session. Keyed on the session's
        // monotonic `id` (never reused within the process) rather than
        // its address, so a rebuilt session can't collide with a freed
        // one and skip the rebuild.
        if session.isCurrentDeviceRemoved {
            RemovedDeviceView(model: model, session: session)
        } else {
            MainTabs(
                session: session,
                initialDetails: model.initialYearDetails,
                selectedYear: model.initialSelectedYear,
            )
            .id(session.id)
        }
    }
}

#if DEBUG
    #Preview("Launch phases") {
        let model = PreviewSupport.onboardingModel()
        let launcher = WhereLaunch.makeLauncher(model: model, reason: .userForeground)
        RootView(model: model, launcher: launcher, primaryAppIconName: "AppIcon")
            .task { await launcher.run() }
    }
#endif
