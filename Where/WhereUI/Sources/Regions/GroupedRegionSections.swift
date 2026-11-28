import RegionKit
import SwiftUI

/// The manual-day form and planning picker show **Your regions**, **Used this year**,
/// and **More regions**. Each caller supplies its row to toggle day membership
/// or choose a planning region.
///
/// Empty upper groups are omitted, and "More regions" opens expanded when
/// there's nothing above it (so the list never appears fully collapsed). The
/// grouping's membership is stable, so rows never jump as they're toggled.
struct GroupedRegionSections<Row: View>: View {
    let grouping: RegionGrouping
    /// An optional footer under the "Your regions" section (the manual-day form
    /// uses it to explain additive union; the picker leaves it `nil`).
    var yoursFooter: String?
    @ViewBuilder var row: (Region) -> Row

    @State private var showMore = false

    var body: some View {
        Group {
            if !grouping.primary.isEmpty {
                PrimaryRegionsSection(regions: grouping.primary, footer: yoursFooter, row: row)
            }

            if !grouping.usedThisYear.isEmpty {
                Section(String(localized: .regionGroupUsedThisYear)) {
                    ForEach(grouping.usedThisYear, id: \.self, content: row)
                }
            }

            Section {
                MoreRegionsDisclosure(regions: grouping.other, isExpanded: $showMore, row: row)
            }
        }
        .task { showMore = grouping.hasNoGroupsBeforeOther }
    }
}

private struct PrimaryRegionsSection<Row: View>: View {
    let regions: [Region]
    let footer: String?
    @ViewBuilder let row: (Region) -> Row

    var body: some View {
        Section {
            ForEach(regions, id: \.self, content: row)
        } header: {
            Text(String(localized: .regionGroupYours))
        } footer: {
            if let footer {
                Text(footer)
            }
        }
    }
}

private struct MoreRegionsDisclosure<Row: View>: View {
    let regions: [Region]
    @Binding var isExpanded: Bool
    @ViewBuilder let row: (Region) -> Row

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(regions, id: \.self, content: row)
        } label: {
            Text(String(localized: .regionGroupMore))
        }
    }
}

#if DEBUG
    #Preview { GroupedRegionsExample() }

    private struct GroupedRegionsExample: View {
        var body: some View {
            Form {
                GroupedRegionSections(
                    grouping: RegionGrouping(
                        available: [.california, .newYork, .ontario, .europeanUnion, .other],
                        primary: [.california, .newYork],
                        usedThisYear: [.ontario],
                    ),
                    yoursFooter: nil,
                ) { region in
                    Text(region.localizedName)
                }
            }
            .whereBroadwayRoot()
        }
    }
#endif
