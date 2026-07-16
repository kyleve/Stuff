import SwiftUI
import WhereCore

/// Settings screen for editing your primary regions after onboarding: reuses
/// the same picker and per-region customization the first run uses. Loads the
/// current picks, lets you add/remove (up to the cap) and re-style each, and
/// commits on Save.
struct RegionsSettingsView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The picker/customization model, built once the current picks load.
    @State private var model: PrimaryRegionSelectionModel?
    @State private var phase: Phase = .pick
    @State private var isSaving = false

    private enum Phase: Hashable {
        case pick
        case customize
    }

    private static let logger = WhereLog.channel(.model)

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle(Strings.regionsManageTitle)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(Strings.commonCancel) { dismiss() }
                            }
                        }
                }
            }
        }
        .task { await loadIfNeeded() }
    }

    @ViewBuilder
    private func content(_ model: PrimaryRegionSelectionModel) -> some View {
        switch phase {
            case .pick:
                RegionPickerView(model: model)
                    .navigationTitle(Strings.regionsManageTitle)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Strings.commonCancel) { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Strings.onboardingNext) { phase = .customize }
                                .disabled(!model.hasSelection)
                        }
                    }
            case .customize:
                // `RegionCustomizeView` supplies its own Back/Done toolbar; Back
                // returns to the pick phase, Done saves.
                RegionCustomizeView(
                    model: model,
                    onBack: { phase = .pick },
                    onFinish: { save(model) },
                )
        }
    }

    private func loadIfNeeded() async {
        guard model == nil else { return }
        do {
            let existing = try await session.services.primaryRegions()
            model = PrimaryRegionSelectionModel(existing: existing)
        } catch {
            Self.logger.warning("Failed to load primary regions for editing")
            // Fall back to an empty picker rather than a stuck spinner.
            model = PrimaryRegionSelectionModel()
        }
    }

    private func save(_ model: PrimaryRegionSelectionModel) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await model.commit(using: session)
            } catch {
                Self.logger.warning("Failed to save primary region edits")
            }
            dismiss()
        }
    }
}

#if DEBUG
    #Preview {
        RegionsSettingsView()
            .environment(PreviewSupport.loadedSession())
            .whereBroadwayRoot()
    }
#endif
