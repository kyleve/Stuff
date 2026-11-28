import Foundation
import Observation
import RegionKit

/// Search and browsing state for one presentation of the primary-region picker.
@MainActor
@Observable
final class RegionPickerModel {
    let draft: PrimaryRegionDraft
    private let usedThisYear: Set<Region>
    var expandedCountries: Set<RegionCatalog.Node.ID?> = []

    init(draft: PrimaryRegionDraft, usedThisYear: Set<Region> = []) {
        self.draft = draft
        self.usedThisYear = usedThisYear
    }

    /// A backup merge can restore more than five picks. The newest five appear at the top.
    /// Earlier picks remain checked in browse and search until the user removes them.
    var selectedNewestFirst: [Region] {
        Array(draft.selectedRegions.reversed().prefix(PrimaryRegionDraft.maxSelection))
    }

    struct Browse {
        let usedThisYear: [Region]
        let countryGroups: [CountryGroup]
    }

    /// Countries include all remaining regions. A year shortcut is visible while its country is
    /// closed.
    var browse: Browse {
        let highlighted = selectedNewestFirst
        let remaining = draft.available.filter { !highlighted.contains($0) }
        let groups = CountryGroup.groups(for: remaining)
        let expanded = groups.filter { expandedCountries.contains($0.id) }.flatMap(\.regions)
        let shortcutRegions = usedThisYear.subtracting(expanded)
        let shortcuts = remaining.filter { $0 != .other && shortcutRegions.contains($0) }
        return Browse(usedThisYear: shortcuts, countryGroups: groups)
    }

    struct CountryGroup: Identifiable {
        let country: RegionCatalog.Node?
        var regions: [Region]
        var id: RegionCatalog.Node.ID? {
            country?.id
        }

        fileprivate static func groups(for regions: [Region]) -> [Self] {
            let catalog = RegionCatalog.shared
            var groups: [Self] = []
            for region in regions {
                let parent = catalog.node(for: region).flatMap(catalog.parent(of:))
                let country = parent?.kind == .country ? parent : nil
                if let index = groups.firstIndex(where: { $0.id == country?.id }) {
                    groups[index].regions.append(region)
                } else {
                    groups.append(Self(country: country, regions: [region]))
                }
            }
            return groups
        }
    }

    /// Both supported countries use a two-letter postal code in their subdivision IDs.
    struct SubdivisionCode {
        let country: String
        let subdivision: String
    }

    var searchText = ""

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    enum SearchResults: Equatable {
        case noMatches
        /// All matches already appear in the selected section.
        case allSelected
        case available([Region])
    }

    /// Exact postal-code matches precede name matches from either country.
    var searchResults: SearchResults {
        let query = searchQuery
        let postalCode = query.uppercased()
        var codeMatches: [Region] = []
        var nameMatches: [Region] = []
        for region in draft.available {
            if code(for: region)?.subdivision == postalCode {
                codeMatches.append(region)
            } else if query.isEmpty || region.localizedName.localizedStandardContains(query) {
                nameMatches.append(region)
            }
        }
        let matches = codeMatches + nameMatches
        guard !matches.isEmpty else { return .noMatches }
        let highlighted = selectedNewestFirst
        let remaining = matches.filter { !highlighted.contains($0) }
        return remaining.isEmpty ? .allSelected : .available(remaining)
    }

    func code(for region: Region) -> SubdivisionCode? {
        let parts = region.rawValue.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, parts[0] == "us" || parts[0] == "ca", parts[1].count == 2
        else { return nil }
        return SubdivisionCode(country: parts[0].uppercased(), subdivision: String(parts[1]))
    }
}
