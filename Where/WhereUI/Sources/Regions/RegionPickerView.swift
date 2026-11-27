import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Picks primary regions in onboarding and Settings. Search and country browsing
/// both edit the same ordered selection.
struct RegionPickerView: View {
    @Bindable var model: PrimaryRegionSelectionModel
    @State private var expandedCountries: Set<RegionCatalog.Node.ID?> = []
    @FocusState private var searchFocused: Bool

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        VStack(spacing: stylesheet.spacing.medium) {
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                searchField
                if !stylesheet.regionPicker.scrollsSelection {
                    selection
                }
            }
            .padding(.horizontal, stylesheet.spacing.xxLarge)
            .whereContentRoot()

            List {
                if stylesheet.regionPicker.scrollsSelection {
                    selection
                        .listRowSeparator(.hidden)
                }
                if model.isSearching {
                    results
                } else {
                    browse
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .whereFormRoot()
        }
        // Settings reuses the selection draft when Manage is opened again.
        .onDisappear { model.searchText = "" }
    }

    private var searchField: some View {
        let prompt = String(localized: .regionPickerSearchByNameOrAbbreviation)
        return HStack(spacing: 0) {
            HStack(spacing: stylesheet.spacing.medium) {
                Image(systemSymbol: .magnifyingglass)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(text: $model.searchText) { EmptyView() }
                    .textFieldStyle(.plain)
                    // A native placeholder applies extra dimming on this filled surface.
                    .background(alignment: .leading) {
                        if model.searchText.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                Text(prompt)
                                Text(String(localized: .regionPickerSearchPrompt))
                                Text(String(localized: .regionPickerCompactSearchPrompt))
                            }
                            .foregroundStyle(stylesheet.regionPicker.searchPromptColor)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityLabel(prompt)
            }
            .padding(.leading, stylesheet.spacing.large)
            .padding(
                .trailing,
                model.searchText.isEmpty ? stylesheet.spacing.large : stylesheet.spacing.medium,
            )
            .frame(minHeight: stylesheet.regionPicker.minimumControlHeight)
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { searchFocused = true })

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .foregroundStyle(.secondary)
                        .frame(
                            minWidth: stylesheet.regionPicker.minimumControlHeight,
                            minHeight: stylesheet.regionPicker.minimumControlHeight,
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: .regionPickerClearSearch))
            }
        }
        .background(
            .quaternary,
            in: .rect(cornerRadius: stylesheet.regionPicker.searchCornerRadius),
        )
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            if model.hasSelection {
                Text(WhereFormat.regionPickerSelectionCount(
                    selected: model.selectionCount,
                    max: PrimaryRegionSelectionModel.maxSelection,
                ))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits([.isHeader, .updatesFrequently])

                switch stylesheet.regionPicker.chipLayout {
                    case .inline:
                        ScrollView(.horizontal) {
                            HStack(spacing: stylesheet.spacing.small) { selectionChips }
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    case .stacked:
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            selectionChips
                        }
                }

                if model.isAtCapacity {
                    Text(WhereFormat
                        .regionPickerAtCapacity(max: PrimaryRegionSelectionModel.maxSelection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: .regionPickerSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionChips: some View {
        ForEach(model.selectedRegions, id: \.self) { region in
            Button {
                model.toggle(region)
            } label: {
                HStack(spacing: stylesheet.spacing.small) {
                    Text(region.localizedName)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Image(systemSymbol: .xmark)
                        .imageScale(.small)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, stylesheet.spacing.large)
                .padding(.vertical, stylesheet.spacing.small)
                .background(.quaternary, in: .capsule)
                .frame(minHeight: stylesheet.regionPicker.minimumControlHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WhereFormat.regionPickerRemoveSelection(region))
        }
    }

    @ViewBuilder
    private var results: some View {
        let matches = model.filteredRegions
        if matches.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
                .listRowSeparator(.hidden)
        } else {
            Section(String(localized: .regionPickerSearchResults)) {
                ForEach(matches, id: \.self) { region in
                    regionRow(region, includesCountryCode: true)
                }
            }
        }
    }

    @ViewBuilder
    private var browse: some View {
        if model.isGrouped, !model.grouping.usedThisYear.isEmpty {
            Section(String(localized: .regionGroupUsedThisYear)) {
                ForEach(model.grouping.usedThisYear, id: \.self) { region in
                    regionRow(region, includesCountryCode: true)
                }
            }
        }
        Section(String(localized: .regionPickerBrowseByCountry)) {
            ForEach(model.countryGroups) { group in
                DisclosureGroup(isExpanded: $expandedCountries[includes: group.id]) {
                    ForEach(group.regions, id: \.self) { region in
                        regionRow(region, includesCountryCode: false)
                    }
                } label: {
                    countryLabel(group)
                }
            }
        }
    }

    private func countryLabel(_ group: PrimaryRegionSelectionModel.CountryGroup) -> some View {
        let name = group.country?.localizedName ?? String(localized: .regionGroupMore)
        let count = WhereFormat.regionPickerRegionCount(group.regions.count)
        return HStack(spacing: stylesheet.spacing.medium) {
            Group {
                switch group.country?.id {
                    case .init(rawValue: "united-states"): Text(verbatim: "🇺🇸")
                    case .init(rawValue: "canada"): Text(verbatim: "🇨🇦")
                    default: Image(systemSymbol: .globe)
                }
            }
            .accessibilityHidden(true)
            LabeledContent(name) { Text(count) }
        }
    }

    private func regionRow(_ region: Region, includesCountryCode: Bool) -> some View {
        let style = regionStyles.style(for: region)
        let selected = model.isSelected(region)
        let codeLabel = model.code(for: region).map { code in
            includesCountryCode ? "\(code.country) · \(code.subdivision)" : code.subdivision
        }
        return Button {
            model.toggle(region)
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
                Text(style.emoji)
                    .accessibilityHidden(true)
                Text(region.localizedName)
                Spacer(minLength: 0)
                if let codeLabel {
                    Text(verbatim: codeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemSymbol: .checkmark)
                        .fontWeight(.semibold)
                        .foregroundStyle(style.tint)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .accessibilityLabel(region.localizedName)
        .accessibilityValue(codeLabel ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(!model.canToggle(region))
    }
}

/// Writable membership lets each native disclosure keep its expansion across searches.
extension Set<RegionCatalog.Node.ID?> {
    fileprivate subscript(includes id: Element) -> Bool {
        get { contains(id) }
        set {
            if newValue { insert(id) } else { remove(id) }
        }
    }
}

#if DEBUG
    extension RegionPickerView: SnapshotProviding {
        private static func selectedSnapshotModel(search: String = "")
            -> PrimaryRegionSelectionModel
        {
            let model = PrimaryRegionSelectionModel()
            model.toggle(.california)
            model.toggle(.ontario)
            model.searchText = search
            return model
        }

        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(
                    name: "AvailableRegions",
                    configurations: [
                        .init(device: .iPhoneFullContent),
                        .init(dynamicType: .accessibility5, device: .iPhoneFullContent),
                    ],
                ) {
                    NavigationStack {
                        RegionPickerView(model: selectedSnapshotModel())
                    }
                },
                whereSnapshot(
                    name: "Search",
                    configurations: [.init(device: .iPhoneFullContent)],
                ) {
                    NavigationStack {
                        RegionPickerView(model: selectedSnapshotModel(search: "ON"))
                            .navigationTitle(String(localized: .settingsRegionsManage))
                            .navigationBarTitleDisplayMode(.inline)
                    }
                },
            ]
        }
    }
#endif

#if DEBUG
    #Preview { RegionPickerView.snapshotPreviews }

    #Preview("Empty") {
        RegionPickerView(model: PrimaryRegionSelectionModel())
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension RegionPickerView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(RegionPickerView.self) { id, world in
            .init(
                id: id,
                title: "Region Picker",
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "list",
                        title: "List",
                        world: world,
                    ) {
                        RegionPickerView(model: PreviewSupport.primaryRegionSelectionModel())
                    },
                ],
            )
        }
    }
#endif
