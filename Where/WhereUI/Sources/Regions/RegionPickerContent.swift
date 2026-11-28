import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct RegionPickerContent: View {
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
        if model.draft.isAtCapacity {
            rows.append(.message(.atCapacity))
        }

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
                    RegionPickerSelectionMessage(draft: model.draft)
                case .atCapacity:
                    Text(WhereFormat
                        .regionPickerAtCapacity(max: PrimaryRegionDraft.maxSelection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .usedThisYear:
                    RegionPickerHeading(title: String(localized: .regionGroupUsedThisYear))
                case .browse:
                    RegionPickerHeading(title: String(localized: .regionPickerBrowseByCountry))
                case .search:
                    RegionPickerHeading(title: String(localized: .regionPickerSearchResults))
                case .noMatches: ContentUnavailableView.search(text: model.searchText)
            }
        }
        .listRowSeparator(.hidden)
    }
}

private struct RegionPickerSelectionMessage: View {
    let draft: PrimaryRegionDraft

    var body: some View {
        if draft.hasSelection {
            RegionPickerHeading(title: WhereFormat.regionPickerSelectionCount(
                selected: draft.selectedRegions.count,
                max: PrimaryRegionDraft.maxSelection,
            ))
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            Text(String(localized: .regionPickerSubtitle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RegionPickerHeading: View {
    let title: String

    var body: some View {
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
        let name = group.country?.localizedName ?? String(localized: .regionGroupMore)
        let count = WhereFormat.regionPickerRegionCount(group.regions.count)
        // The country's children are sibling list rows so they can move directly into selection.
        DisclosureGroup(isExpanded: $isExpanded) {
            EmptyView()
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
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
}

/// Writable membership lets each native disclosure keep its expansion across searches.
extension Set<RegionCatalog.Node.ID?> {
    fileprivate subscript(includes id: Element) -> Bool {
        get { contains(id) }
        set {
            if newValue {
                insert(id)
            } else {
                remove(id)
            }
        }
    }
}

#if DEBUG
    #Preview { RegionPickerView.snapshotPreviews }
#endif
