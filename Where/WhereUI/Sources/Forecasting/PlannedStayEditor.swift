import RegionKit
import SwiftUI

/// Sheet for setting or removing the inclusive departure day for the currently
/// focused region.
struct PlannedStayEditor: View {
    private enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    let region: Region
    let model: LocationForecastModel

    @Environment(\.dismiss) private var dismiss
    @State private var through: Date
    @State private var saveState: SaveState = .idle

    init(region: Region, model: LocationForecastModel) {
        self.region = region
        self.model = model
        _through = State(initialValue: model.departureDate(for: region))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WhereDatePicker(
                        String(localized: .locationForecastEditorDate),
                        selection: $through,
                        earliest: model.minimumDepartureDate,
                        displayedComponents: .date,
                    )
                } footer: {
                    Text(String(localized: .locationForecastEditorFooter))
                }

                if case let .failed(message) = saveState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if model.activePlannedStay?.region == region {
                    Section {
                        Button(
                            String(localized: .locationForecastRemovePlan),
                            role: .destructive,
                            action: removePlan,
                        )
                    }
                }
            }
            .navigationTitle(String(localized: .locationForecastEditorTitle))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saveState == .saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel), action: dismiss.callAsFunction)
                        .disabled(saveState == .saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saveState == .saving {
                        ProgressView()
                    } else {
                        Button(String(localized: .commonSave), action: save)
                    }
                }
            }
        }
    }

    private func save() {
        saveState = .saving
        Task {
            do {
                try await model.set(region: region, through: through)
                dismiss()
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }

    private func removePlan() {
        saveState = .saving
        Task {
            do {
                try await model.clear()
                dismiss()
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}
