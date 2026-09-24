import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings screen for editing primary regions after onboarding. It opens on
/// the current regions, lets one region's appearance be edited at a time, and
/// keeps add/remove work behind a separate route to the shared picker.
struct RegionsSettingsView: View {
    /// Regions with days in the selected year, so the picker can surface a
    /// "used this year" group. Passed by `SettingsView` from the report.
    var usedThisYear: Set<Region> = []

    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The shared membership and appearance draft, built once the current picks load.
    @State private var model: PrimaryRegionSelectionModel?
    @State private var isSaving = false
    @State private var saveError = SaveErrorAlertState()

    private enum Destination: Hashable {
        case appearance(Region)
        case manage
    }

    private static let logger = WhereLog.session(RegionsSettingsViewLog.self)

    var body: some View {
        @Bindable var saveError = saveError

        // Presented as a sheet from Settings, so it owns its navigation stack and
        // explicit Cancel/Done points — making the commit boundary clear.
        NavigationStack {
            Group {
                if let model {
                    overview(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle(String(localized: .settingsRegionsSection))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: .commonCancel)) { dismiss() }
                            }
                        }
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                if let model {
                    destinationView(destination, model: model)
                }
            }
        }
        .task { await loadIfNeeded() }
        .interactiveDismissDisabled(isSaving)
        .alert(
            String(localized: .settingsRegionsSaveErrorTitle),
            isPresented: $saveError.isPresented,
        ) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            if let message = saveError.message {
                Text(message)
            }
        }
        // Log View Mode: reveal an inspect badge for the region-editor events. A
        // no-op in release.
        .debugLogInspectable(WhereLog.session(RegionsSettingsViewLog.self))
    }

    private func overview(_ model: PrimaryRegionSelectionModel) -> some View {
        List {
            Section(String(localized: .regionGroupYours)) {
                if model.selectedRegions.isEmpty {
                    Text(String(localized: .settingsRegionsEmpty))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.selectedRegions, id: \.self) { region in
                        NavigationLink(value: Destination.appearance(region)) {
                            regionRow(region, model: model)
                        }
                    }
                }
            }

            Section {
                NavigationLink(value: Destination.manage) {
                    Label(
                        String(localized: .settingsRegionsManage),
                        systemSymbol: .map,
                    )
                }
            }
        }
        .disabled(isSaving)
        .navigationTitle(String(localized: .settingsRegionsSection))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: .commonCancel)) { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityLabel(String(localized: .commonSave))
                } else {
                    Button(String(localized: .commonDone)) { save(model) }
                        .disabled(!model.hasSelection)
                }
            }
        }
    }

    private func regionRow(
        _ region: Region,
        model: PrimaryRegionSelectionModel,
    ) -> some View {
        let appearance = model.appearance(for: region)
        return HStack {
            Text(appearance.emoji)
                .accessibilityHidden(true)
            Text(region.localizedName)
            Spacer(minLength: 0)
            Image(systemSymbol: appearance.symbolName.sfSymbol)
                .foregroundStyle(appearance.color.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func destinationView(
        _ destination: Destination,
        model: PrimaryRegionSelectionModel,
    ) -> some View {
        switch destination {
            case let .appearance(region):
                RegionAppearanceEditor(model: model, region: region)
                    .navigationTitle(region.localizedName)
                    .navigationBarTitleDisplayMode(.inline)
            case .manage:
                RegionPickerView(model: model)
                    .navigationTitle(String(localized: .settingsRegionsManage))
                    .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadIfNeeded() async {
        guard model == nil else { return }
        let built: PrimaryRegionSelectionModel
        do {
            let existing = try await session.services.primaryRegions()
            built = PrimaryRegionSelectionModel(existing: existing)
        } catch {
            Self.logger(attachments: [.error(error, name: "load-error")]) {
                .primaryRegionsLoadFailed(description: error.localizedDescription)
            }
            // Fall back to an empty picker rather than a stuck spinner.
            built = PrimaryRegionSelectionModel()
        }
        // Group the list (Your regions / Used this year / More) — Settings only.
        built.applyGrouping(usedThisYear: usedThisYear)
        model = built
    }

    private func save(_ model: PrimaryRegionSelectionModel) {
        guard !isSaving else { return }
        saveError.message = nil
        isSaving = true
        Task {
            do {
                try await model.commit(using: session)
                dismiss()
            } catch {
                Self.logger(attachments: [.error(error, name: "save-error")]) {
                    .primaryRegionsSaveFailed(description: error.localizedDescription)
                }
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }
}

extension RegionsSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .regions
    }

    enum Item: SettingsItem {
        case regions

        var title: String {
            switch self {
                case .regions: String(localized: .settingsRegionsSection)
            }
        }

        var keywords: [String] {
            switch self {
                case .regions: splitKeywords(String(localized: .settingsKeywordsRegions))
            }
        }
    }
}

#if DEBUG
    extension RegionsSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Overview",
                configurations: .fullContentScreenDefaults,
            ) {
                RegionsSettingsView()
                    .environment(PreviewSupport.loadedSession())
            }
        }
    }

    #Preview {
        RegionsSettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension RegionsSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            RegionsSettingsView.self,
            title: "Regions",
        ) { world in
            RegionsSettingsView(
                usedThisYear: Set(
                    world.report.report.map { Array($0.totals.keys) } ?? [],
                ),
            )
        }
    }
#endif
