import LifecycleKit
import SFSafeSymbols
import SwiftUI
@_spi(Testing) import WhereCore

struct OnboardingRecordingChoice: View {
    let flow: OnboardingFlowModel
    @Environment(WhereModel.self) private var model
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: stylesheet.spacing.xxxLarge) {
                    Spacer(minLength: 0)
                    Image(systemSymbol: flow.installationContext.currentDevice.kind.systemSymbol)
                        .font(stylesheet.typography.onboardingIcon)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    OnboardingHeading(
                        title: Text(recordingTitle),
                        description: Text(String(localized: .onboardingRecordingDescription)),
                    )
                    Spacer(minLength: 0)

                    VStack(spacing: stylesheet.spacing.large) {
                        OnboardingRecordingSettings(flow: flow)
                        // Request Always-location only after confirming enabled recording.
                        OnboardingContinueButton { flow.finish(using: model) }
                    }
                    .disabled(
                        flow.isFinishing || model.isCompletingOnboarding
                            || flow.deviceDiscovery == .loading,
                    )
                }
                .padding(.horizontal, stylesheet.spacing.xxxLarge)
                .padding(.bottom, stylesheet.spacing.xxxLarge)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .whereContentRoot()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await flow.discoverRecordingDevices(using: model) }
    }

    private var recordingTitle: LocalizedStringResource {
        switch flow.installationContext.currentDevice.kind {
            case .phone: .onboardingRecordingPhoneTitle
            case .tablet: .onboardingRecordingTabletTitle
            case .computer, .watch, .other: .onboardingRecordingOtherTitle
        }
    }
}

private struct OnboardingRecordingSettings: View {
    @Bindable var flow: OnboardingFlowModel
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
            OnboardingRecordingDiscovery(discovery: flow.deviceDiscovery)
            Toggle(
                String(localized: .settingsDevicesAutomaticRecording),
                isOn: $flow.recordingEnabled,
            )
            Text(recordingRecommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct OnboardingRecordingDiscovery: View {
    let discovery: OnboardingFlowModel.DeviceDiscovery

    var body: some View {
        switch discovery {
            case .idle, .loading:
                ProgressView(String(localized: .onboardingRecordingChecking))
            case let .ready(recommendation):
                if recommendation.recentRecordingDevice != nil {
                    Label(
                        String(localized: .onboardingRecordingRecent),
                        systemSymbol: .iphoneRadiowavesLeftAndRight,
                    )
                }
            case let .failed(description):
                Label(description, systemSymbol: .icloudSlash)
                    .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Recording choice") {
        OnboardingView(
            gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
            installationContext: .testing,
            startsAtRecordingChoice: true,
        )
        .environment(PreviewSupport.onboardingModel())
        .whereBroadwayRoot()
    }
#endif
