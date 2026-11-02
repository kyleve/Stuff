#if DEBUG
    import Foundation
    import LifecycleKit
    import Observation
    import PeriscopeCore
    import WhereCore

    /// Owns an independent first-run gate. It never starts a session or installs app integrations.
    @MainActor
    final class DeveloperOnboardingModel {
        let model: WhereModel
        let runner: LifecycleRunner<Void>
        private var isClosed = false

        init(
            deviceKind: RecordingDeviceKind,
            diagnostics: DiagnosticReportingConfiguration,
            now: @escaping @Sendable () -> Date,
        ) {
            let context = InstallationRecordingContext(
                currentDevice: CurrentRecordingDevice(
                    id: RecordingDeviceID(rawValue: UUID()),
                    systemName: String(localized: .developerOnboardingTitle),
                    kind: deviceKind,
                ),
                registeredAt: now(),
                recordingChoice: .unconfirmed,
                isRejoining: false,
            )
            let model = WhereModel(
                preferences: WherePreferences(store: InMemoryKeyValueStore()),
                installationContextStore: InMemoryInstallationRecordingContextStore(
                    context: context,
                ),
                makeBootstrap: {
                    DeveloperOnboardingAssembler(installationContextStore: $0, now: now)
                },
                logSystem: Periscope(configuration: Periscope.Configuration(), sinks: []),
                effectiveDiagnosticReportingConfiguration: diagnostics,
                now: now,
            )
            self.model = model
            runner = LifecycleRunner(
                reason: .userForeground,
                plan: LaunchPlan(OnboardingGate(model: model)),
            )
        }

        private var pendingGate: LifecycleGateHandle? {
            if case let .awaitingGate(handle) = runner.phase { handle } else { nil }
        }

        func close() {
            isClosed = true
            if case let .awaitingGate(handle) = runner.phase {
                handle.fail(CancellationError())
            }
        }

        func run() async {
            guard !isClosed else { return }
            // The runner owns its drive task. Watch a late-arriving gate too, so
            // dismissing during initial launch cannot leave that task parked forever.
            let gateObserver = Task {
                for await handle in Observations({ self.pendingGate }) {
                    if isClosed, let handle {
                        handle.fail(CancellationError())
                    }
                }
            }
            await runner.run()
            gateObserver.cancel()
            await gateObserver.value
        }

        func releaseScope() async {
            await model.endSession()
        }
    }
#endif
