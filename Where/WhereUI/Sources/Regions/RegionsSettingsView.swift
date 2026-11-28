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
    @State private var draft: PrimaryRegionDraft?
    @State private var isSaving = false
    @State private var saveError = SaveErrorAlertState()

    enum Destination: Hashable {
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
                if let draft {
                    RegionsSettingsOverview(draft: draft, isSaving: isSaving) { save(draft) }
                        .navigationDestination(for: Destination.self) {
                            RegionSettingsDestination(
                                destination: $0,
                                draft: draft,
                                usedThisYear: usedThisYear,
                            )
                            .whereScreenBoundary()
                        }
                } else {
                    RegionsSettingsLoading()
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

    private func loadIfNeeded() async {
        guard draft == nil else { return }
        let built: PrimaryRegionDraft
        do {
            let existing = try await session.services.primaryRegions()
            built = PrimaryRegionDraft(existing: existing)
        } catch {
            Self.logger.primaryRegionsLoadFailed(
                error: .restricted(.errorDetails, error),
            )
            // Fall back to an empty picker rather than a stuck spinner.
            built = PrimaryRegionDraft()
        }
        draft = built
    }

    private func save(_ draft: PrimaryRegionDraft) {
        guard !isSaving else { return }
        saveError.message = nil
        isSaving = true
        Task {
            do {
                try await draft.commit(using: session)
                dismiss()
            } catch {
                Self.logger.primaryRegionsSaveFailed(
                    error: .restricted(.errorDetails, error),
                )
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct RegionsSettingsLoading: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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

private struct RegionSettingsDestination: View {
    let destination: RegionsSettingsView.Destination
    @Bindable var draft: PrimaryRegionDraft
    let usedThisYear: Set<Region>

    var body: some View {
        switch destination {
            case let .appearance(region):
                RegionAppearanceEditor(region: region, appearance: $draft[appearanceFor: region])
                    .navigationTitle(region.localizedName)
                    .navigationBarTitleDisplayMode(.inline)
            case .manage:
                RegionPickerView(draft: draft, usedThisYear: usedThisYear)
                    .navigationTitle(String(localized: .settingsRegionsManage))
                    .navigationBarTitleDisplayMode(.inline)
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
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                ],
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
