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
                Section {
                    ForEach(grouping.primary, id: \.self, content: row)
                } header: {
                    Text(String(localized: .regionGroupYours))
                } footer: {
                    if let yoursFooter {
                        Text(yoursFooter)
                    }
                }
            }

            if !grouping.usedThisYear.isEmpty {
                Section(String(localized: .regionGroupUsedThisYear)) {
                    ForEach(grouping.usedThisYear, id: \.self, content: row)
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showMore) {
                    ForEach(grouping.other, id: \.self, content: row)
                } label: {
                    Text(String(localized: .regionGroupMore))
                }
            }
        }
        .task { showMore = grouping.hasNoGroupsBeforeOther }
    }
}

#if DEBUG
    #Preview {
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
#endif
