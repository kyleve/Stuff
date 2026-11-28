import RegionKit
import SFSafeSymbols
import SwiftUI

/// The selectable feature list shared by the bounded developer map screen and
/// its full-content snapshot.
struct RegionMapLegend: View {
    let kind: RegionGeometryPurpose
    let groups: [RegionMapLegendGroup]
    let selectedTitle: String?
    let color: (RegionMapLegendGroup) -> Color
    let onSelect: (String?) -> Void

    var body: some View {
        List {
            Section {
                if selectedTitle != nil {
                    Button(String(localized: .regionMapShowAll)) { onSelect(nil) }
                }
                ForEach(groups) { group in
                    RegionMapLegendButton(
                        group: group,
                        isSelected: group.title == selectedTitle,
                        tint: color(group),
                        onSelect: onSelect,
                    )
                }
            } header: {
                Text(String(localized: .regionMapLegendHeader))
            } footer: {
                Text(WhereFormat.regionMapKindFooter(kind))
            }
        }
    }
}

#if DEBUG
    #Preview { RegionMapLegendPreview() }

    private struct RegionMapLegendPreview: View {
        private let groups = [
            RegionMapLegendGroup(
                title: Region.california.localizedName,
                region: .california,
                outlineCount: 2,
            ),
            RegionMapLegendGroup(
                title: Region.newYork.localizedName,
                region: .newYork,
                outlineCount: 1,
            ),
        ]

        var body: some View {
            RegionMapLegend(
                kind: .display,
                groups: groups,
                selectedTitle: Region.california.localizedName,
                color: { group in
                    group.region.map { RegionStyle.fallbackStyle(for: $0).tint } ?? .gray
                },
                onSelect: { _ in },
            )
            .whereBroadwayRoot()
        }
    }
#endif
