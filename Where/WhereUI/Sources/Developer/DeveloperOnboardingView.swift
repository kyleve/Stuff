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
            .environment(preview.model)
            .environment(WhereSession?.none)
            .environment(\.isInDemoMode, true)
            .environment(\.periscopeInspector, nil)
            .whereBroadwayRoot(theme: preview.model.theme)
            .accessibilityAddTraits(.isModal)
            .task {
                await preview.run()
                if case .ready = preview.runner.phase {
                    dismiss()
                }
            }
            .onDisappear {
                preview.close()
                Task { await preview.releaseScope() }
            }
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
