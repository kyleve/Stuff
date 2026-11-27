import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Mounts a fresh picker model for each visit while the caller retains the edit draft.
struct RegionPickerView: View {
    private let makeModel: () -> RegionPickerModel

    init(draft: PrimaryRegionDraft, usedThisYear: Set<Region> = []) {
        self.init { RegionPickerModel(draft: draft, usedThisYear: usedThisYear) }
    }

    private init(makeModel: @escaping () -> RegionPickerModel) {
        self.makeModel = makeModel
    }

    var body: some View {
        ObservableHostingView(makeModel) { RegionPickerContent(model: $0) }
    }
}

private struct RegionPickerContent: View {
    @Bindable var model: RegionPickerModel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(rows) { row in
                    switch row {
                        case let .message(message):
                            RegionPickerMessageRow(message: message, model: model)
                        case let .country(group):
                            RegionPickerCountryRow(
                                group: group,
                                isExpanded: $model.expandedCountries[includes: group.id],
                            )
                        case let .region(region, includesCountryCode):
                            RegionPickerRegionRow(
                                region: region,
                                includesCountryCode: includesCountryCode,
                                model: model,
                            )
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .whereFormRoot()
            .onChange(of: model.draft.selectedRegions.count) { previous, current in
                if current > previous {
                    withAnimation(stylesheet.regionPicker.selectionAnimation) {
                        proxy.scrollTo(Row.ID.message(.selection), anchor: .top)
                    }
                }
            }
        }
        .searchable(
            text: $model.searchText,
            prompt: String(localized: .regionPickerSearchPrompt),
        )
    }

    /// A region has one native list identity wherever it is displayed, so changing selection
    /// moves the same row between the catalog and the selected rows.
    fileprivate enum Row: Identifiable {
        case region(Region, includesCountryCode: Bool)
        case country(RegionPickerModel.CountryGroup)
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
        if model.draft.isAtCapacity { rows.append(.message(.atCapacity)) }

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
            let browse = model.browse
            if !browse.usedThisYear.isEmpty {
                rows.append(.message(.usedThisYear))
                rows += browse.usedThisYear.map { .region($0, includesCountryCode: true) }
            }
            if !browse.countryGroups.isEmpty {
                rows.append(.message(.browse))
                for group in browse.countryGroups {
                    rows.append(.country(group))
                    if model.expandedCountries.contains(group.id) {
                        rows += group.regions.map { .region($0, includesCountryCode: false) }
                    }
                }
            }
        }
        return rows
    }
}

private struct RegionPickerMessageRow: View {
    let message: RegionPickerContent.Row.Message
    let model: RegionPickerModel

    var body: some View {
        Group {
            switch message {
                case .selection:
                    if model.draft.hasSelection {
                        heading(WhereFormat.regionPickerSelectionCount(
                            selected: model.draft.selectedRegions.count,
                            max: PrimaryRegionDraft.maxSelection,
                        ))
                        .accessibilityAddTraits(.updatesFrequently)
                    } else {
                        Text(String(localized: .regionPickerSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .atCapacity:
                    Text(WhereFormat
                        .regionPickerAtCapacity(max: PrimaryRegionDraft.maxSelection))
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
}

private struct RegionPickerCountryRow: View {
    let group: RegionPickerModel.CountryGroup
    @Binding var isExpanded: Bool
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        // The country's children are sibling list rows so they can move directly into selection.
        DisclosureGroup(isExpanded: $isExpanded) {
            EmptyView()
        } label: {
            label
        }
    }

    private var label: some View {
        let name = group.country?.localizedName ?? String(localized: .regionGroupMore)
        let count = WhereFormat.regionPickerRegionCount(group.regions.count)
        return HStack(spacing: stylesheet.spacing.medium) {
            Group {
                switch group.country?.id {
                    case .some(.unitedStates): Text(verbatim: "🇺🇸")
                    case .some(.canada): Text(verbatim: "🇨🇦")
                    default: Image(systemSymbol: .globe)
                }
            }
            .accessibilityHidden(true)
            LabeledContent(name) { Text(count) }
        }
    }
}

private struct RegionPickerRegionRow: View {
    let region: Region
    let includesCountryCode: Bool
    let model: RegionPickerModel

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let style = regionStyles.style(for: region)
        let selected = model.draft.isSelected(region)
        let codeLabel = model.code(for: region).map { code in
            includesCountryCode ? "\(code.country) · \(code.subdivision)" : code.subdivision
        }
        Button {
            withAnimation(stylesheet.regionPicker.selectionAnimation) {
                model.draft.toggle(region)
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
        .disabled(!model.draft.canToggle(region))
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
        private static func selectedSnapshotModel(search: String = "") -> RegionPickerModel {
            let draft = PrimaryRegionDraft()
            draft.toggle(.california)
            draft.toggle(.ontario)
            let model = RegionPickerModel(draft: draft)
            model.searchText = search
            return model
        }

        static var snapshots: [SnapshotCase] {
            // The system search toolbar needs an attached scene to render its glass.
            var phone = SnapshotConfiguration.Frame.iPhoneFullContent
            phone.scenePolicy = .retained
            return [
                whereSnapshot(
                    name: "AvailableRegions",
                    configurations: [
                        .init(device: phone),
                        .init(dynamicType: .accessibility5, device: phone),
                    ],
                ) {
                    NavigationStack {
                        RegionPickerView { selectedSnapshotModel() }
                    }
                },
                whereSnapshot(
                    name: "Search",
                    configurations: [.init(device: phone)],
                    // The native clear button finishes appearing after the toolbar mounts.
                    settle: .settledAtLeast(minDuration: 1.0),
                ) {
                    NavigationStack {
                        RegionPickerView { selectedSnapshotModel(search: "ON") }
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
        NavigationStack {
            RegionPickerView(draft: PrimaryRegionDraft())
                .navigationTitle(String(localized: .onboardingRegionsTitle))
        }
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
                        RegionPickerView(draft: PreviewSupport.primaryRegionDraft())
                    },
                ],
            )
        }
    }
#endif
