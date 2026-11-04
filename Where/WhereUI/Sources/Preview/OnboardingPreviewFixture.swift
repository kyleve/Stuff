#if DEBUG
    import Foundation
    import LifecycleKit
    @_spi(Testing) import WhereCore

    /// Lazily creates one setup subject only when its snapshot content or readiness hook runs.
    @MainActor
    final class OnboardingPreviewFixture {
        struct State {
            let model: WhereModel
            let flow: OnboardingFlowModel
        }

        private let replacesOldDevice: Bool
        private(set) lazy var state = makeState()

        init(replacesOldDevice: Bool) {
            self.replacesOldDevice = replacesOldDevice
        }

        func prepare() async {
            let state = state
            await state.flow.deviceSetup.discover(
                using: state.model,
                context: state.flow.installationContext,
            )
            while state.flow.deviceSetup.isLoading {
                await Task.yield()
            }
        }

        private func makeState() -> State {
            let preferences = PreviewSupport.previewPreferences()
            let device = RecordingDevice(
                id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
                systemName: "iPhone",
                nickname: "Previous iPhone",
                kind: .phone,
                registeredAt: PreviewSupport.referenceNow,
                lastSeenAt: PreviewSupport.referenceNow,
                removedAt: nil,
                status: .recording,
            )
            let model = WhereModel(
                preferences: preferences,
                installationContextStore: InMemoryInstallationRecordingContextStore(
                    context: .testing,
                ),
                makeBootstrap: { OnboardingPreviewBootstrap(contextStore: $0, devices: [device]) },
                logSystem: PreviewSupport.logSystem,
            )
            let flow = OnboardingFlowModel(
                gate: LifecycleGateHandle(id: LaunchStepID.onboarding, reason: .userForeground),
                installationContext: .testing,
                startsAtRecordingChoice: true,
                initialTheme: .standard,
                preferences: preferences,
            )
            if replacesOldDevice {
                flow.deviceSetup.replacementDeviceID = device.id
                flow.deviceSetup.removesOldDevice = true
            }
            return State(model: model, flow: flow)
        }
    }
#endif
