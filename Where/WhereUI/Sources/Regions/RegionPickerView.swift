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
            searchField
                .padding(.horizontal, stylesheet.spacing.xxLarge)
                .whereContentRoot()

            ScrollViewReader { proxy in
                List {
                    ForEach(rows) { row in
                        switch row {
                            case let .message(message): messageRow(message)
                            case let .country(group): countryRow(group)
                            case let .region(region, includesCountryCode):
                                regionRow(region, includesCountryCode: includesCountryCode)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .whereFormRoot()
                .onChange(of: model.selectionCount) { previous, current in
                    if current > previous {
                        withAnimation(stylesheet.regionPicker.selectionAnimation) {
                            proxy.scrollTo(Row.ID.message(.selection), anchor: .top)
                        }
                    }
                }
            }
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

    /// A region has one native list identity wherever it is displayed, so changing selection
    /// moves the same row between the catalog and the selected rows.
    private enum Row: Identifiable {
        case region(Region, includesCountryCode: Bool)
        case country(PrimaryRegionSelectionModel.CountryGroup)
        case message(Message)

        enum Message: Hashable {
            case selection
            case atCapacity
            case usedThisYear
            case browse
            case search
            case noMatches
        }

        enum ID: Hashable {
            case region(Region)
            case country(RegionCatalog.Node.ID?)
            case message(Message)
        }

        var id: ID {
            switch self {
                case let .region(region, _): .region(region)
                case let .country(group): .country(group.id)
                case let .message(message): .message(message)
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = [.message(.selection)]
        rows += model.selectedNewestFirst.map { .region($0, includesCountryCode: true) }
        if model.isAtCapacity { rows.append(.message(.atCapacity)) }

        if model.isSearching {
            switch model.searchResults {
                case .noMatches:
                    rows.append(.message(.noMatches))
                case .allSelected:
                    break
                case let .available(matches):
                    rows.append(.message(.search))
                    rows += matches.map { .region($0, includesCountryCode: true) }
            }
        } else {
            let browse = model.browse(expandedCountries: expandedCountries)
            if !browse.usedThisYear.isEmpty {
                rows.append(.message(.usedThisYear))
                rows += browse.usedThisYear.map { .region($0, includesCountryCode: true) }
            }
            if !browse.countryGroups.isEmpty {
                rows.append(.message(.browse))
                for group in browse.countryGroups {
                    rows.append(.country(group))
                    if expandedCountries.contains(group.id) {
                        rows += group.regions.map { .region($0, includesCountryCode: false) }
                    }
                }
            }
        }
        return rows
    }

    private func messageRow(_ message: Row.Message) -> some View {
        Group {
            switch message {
                case .selection:
                    if model.hasSelection {
                        heading(WhereFormat.regionPickerSelectionCount(
                            selected: model.selectionCount,
                            max: PrimaryRegionSelectionModel.maxSelection,
                        ))
                        .accessibilityAddTraits(.updatesFrequently)
                    } else {
                        Text(String(localized: .regionPickerSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .atCapacity:
                    Text(WhereFormat
                        .regionPickerAtCapacity(max: PrimaryRegionSelectionModel.maxSelection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .usedThisYear: heading(String(localized: .regionGroupUsedThisYear))
                case .browse: heading(String(localized: .regionPickerBrowseByCountry))
                case .search: heading(String(localized: .regionPickerSearchResults))
                case .noMatches: ContentUnavailableView.search(text: model.searchText)
            }
        }
        .listRowSeparator(.hidden)
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func countryRow(_ group: PrimaryRegionSelectionModel.CountryGroup) -> some View {
        // The country's children are sibling list rows so they can move directly into selection.
        DisclosureGroup(isExpanded: $expandedCountries[includes: group.id]) {
            EmptyView()
        } label: {
            countryLabel(group)
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
            withAnimation(stylesheet.regionPicker.selectionAnimation) {
                model.toggle(region)
            }
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
                Text(style.emoji)
                    .accessibilityHidden(true)
                LabeledContent {
                    if let codeLabel {
                        Text(verbatim: codeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(region.localizedName)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityHint(selected ? WhereFormat.regionPickerRemoveSelection(region) : "")
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
