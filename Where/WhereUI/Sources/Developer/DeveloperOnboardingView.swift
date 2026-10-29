#if DEBUG
    import LifecycleKitUI
    import PeriscopeTools
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// The production onboarding flow in a disposable, independently styled environment.
    struct DeveloperOnboardingView: View {
        @State private var preview: DeveloperOnboardingModel
        @Environment(\.dismiss) private var dismiss
        /// Scene activity is a runtime input for the completion hold, not an appearance trait.
        @Environment(\.scenePhase) private var scenePhase

        init(diagnostics: DiagnosticReportingConfiguration) {
            _preview = State(initialValue: DeveloperOnboardingModel(
                deviceKind: UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone,
                diagnostics: diagnostics,
                now: { Date() },
            ))
        }

        init(preview: DeveloperOnboardingModel) {
            _preview = State(initialValue: preview)
        }

        var body: some View {
            LifecycleContainer(
                preview.runner,
                splash: { _ in ProgressView() },
                failure: { WhereLifecycleFailureView(failure: $0) },
                gates: {
                    GateView(for: OnboardingGate.self) { handle, _ in
                        OnboardingView(
                            gate: handle,
                            installationContext: preview.model.installationRecordingContext,
                        )
                    }
                },
            ) { _ in
                Color.clear
            }
            .safeAreaInset(edge: .top) {
                if !preview.model.onboardingWelcome.isPresented {
                    HStack {
                        Text(String(localized: .developerOnboardingTitle))
                            .font(.headline)
                        Spacer()
                        Button(String(localized: .developerClose), systemSymbol: .xmark) {
                            preview.close()
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                    }
                    .padding()
                    .background(.background)
                }
            }
            .modifier(OnboardingWelcomePresentation(
                model: preview.model.onboardingWelcome,
                destination: .init(phase: preview.runner.phase),
                isPresentationVisible: scenePhase == .active,
                onReveal: dismissAfterWelcome,
            ))
            .environment(preview.model)
            .environment(WhereSession?.none)
            .environment(\.isInDemoMode, true)
            .environment(\.periscopeInspector, nil)
            .whereBroadwayRoot(theme: preview.model.theme)
            .accessibilityAddTraits(.isModal)
            .presentationBackground(.clear)
            .task {
                await preview.run()
            }
            .onDisappear {
                preview.close()
                Task { await preview.releaseScope() }
            }
        }

        private func dismissAfterWelcome() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }

    extension DeveloperOnboardingView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            onboardingSnapshot(name: "Welcome", configurations: .phoneLightDark) {
                DeveloperOnboardingView(preview: DeveloperOnboardingModel(
                    deviceKind: .phone,
                    diagnostics: .defaults(isDebugBuild: true),
                    now: { PreviewSupport.referenceNow },
                ))
            }
        }
    }

    #Preview {
        DeveloperOnboardingView.snapshotPreviews
    }
#endif
