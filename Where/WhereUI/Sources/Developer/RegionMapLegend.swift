import RegionKit
import SwiftUI

/// The selectable feature list shared by the bounded developer map screen and
/// its full-content snapshot.
struct RegionMapLegend: View {
    let kind: RegionGeometryKind
    let groups: [RegionMapLegendGroup]
    let selectedTitle: String?
    let color: (RegionMapLegendGroup) -> Color
    let onSelect: (String?) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        List {
            Section {
                if selectedTitle != nil {
                    Button(String(localized: .regionMapShowAll)) { onSelect(nil) }
                }
                ForEach(groups) { group in
                    Button {
                        onSelect(group.title == selectedTitle ? nil : group.title)
                    } label: {
                        row(group)
                    }
                    .tint(.primary)
                }
            } header: {
                Text(String(localized: .regionMapLegendHeader))
            } footer: {
                Text(WhereFormat.regionMapKindFooter(kind))
            }
        }
    }

    private func row(_ group: RegionMapLegendGroup) -> some View {
        HStack(spacing: stylesheet.spacing.large) {
            Circle()
                .fill(color(group))
                // Developer legend swatch — a fixed dev-tool size, not a themed token.
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(group.title)
            Spacer()
            if group.outlineCount > 1 {
                Text("\(group.outlineCount)")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if group.title == selectedTitle {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
    }
}
