import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct RegionsSettingsOverview: View {
    @Environment(\.dismiss) private var dismiss
    let draft: PrimaryRegionDraft
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        List {
            SelectedRegionsSection(draft: draft)

            Section {
                ManageRegionsLink()
            }
        }
        .whereFormRoot()
        .disabled(isSaving)
        .navigationTitle(String(localized: .settingsRegionsSection))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: .commonCancel)) { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                RegionsSaveControl(
                    isSaving: isSaving,
                    hasSelection: draft.hasSelection,
                    onSave: onSave,
                )
            }
        }
    }
}

private struct RegionsSaveControl: View {
    let isSaving: Bool
    let hasSelection: Bool
    let onSave: () -> Void

    var body: some View {
        if isSaving {
            ProgressView()
                .accessibilityLabel(String(localized: .commonSave))
        } else {
            Button(String(localized: .commonDone)) { onSave() }
                .disabled(!hasSelection)
        }
    }
}

private struct SelectedRegionsSection: View {
    let draft: PrimaryRegionDraft

    var body: some View {
        Section(String(localized: .regionGroupYours)) {
            if draft.selectedRegions.isEmpty {
                Text(String(localized: .settingsRegionsEmpty))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.selectedRegions, id: \.self) { region in
                    RegionAppearanceLink(region: region, draft: draft)
                }
            }
        }
    }
}

private struct RegionAppearanceLink: View {
    let region: Region
    let draft: PrimaryRegionDraft

    var body: some View {
        let appearance = draft[appearanceFor: region]
        NavigationLink(value: RegionsSettingsView.Destination.appearance(region)) {
            HStack {
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
    }
}

private struct ManageRegionsLink: View {
    var body: some View {
        NavigationLink(value: RegionsSettingsView.Destination.manage) {
            Label(
                String(localized: .settingsRegionsManage),
                systemSymbol: .map,
            )
        }
    }
}

#if DEBUG
    #Preview { RegionsSettingsView.snapshotPreviews }
#endif
