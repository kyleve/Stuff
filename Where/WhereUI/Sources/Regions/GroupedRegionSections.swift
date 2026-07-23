import RegionKit
import SwiftUI

/// The shared sectioned layout behind the manual-day region toggles and the
/// primary-region picker's list: **Your regions** / **Used this year** /
/// **More regions** (collapsed). Renders a ``RegionGrouping`` as `Section`s
/// (drop straight into a `Form` or `List`) and lets the caller supply the row
/// so each surface keeps its own affordance — a `Toggle` for day membership, a
/// checkmark button for the capped picker.
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
                    if let yoursFooter { Text(yoursFooter) }
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
