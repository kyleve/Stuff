import SwiftUI
import WhereSurface

struct WhereMenuBarRegionRow: View {
    let region: WhereSurfaceSnapshot.Region

    var body: some View {
        HStack {
            if let emoji = region.emoji, emoji.isEmpty == false {
                Text(verbatim: emoji)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: region.symbolName ?? "location.fill")
                    .accessibilityHidden(true)
            }
            Text(verbatim: region.name)
        }
    }
}
