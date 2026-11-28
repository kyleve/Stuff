import RegionKit
import SwiftUI

#if DEBUG

    struct RegionOutlineSecurityBorderPreview: View {
        @State private var path = Path()
        private let cache = RegionOutlinePathCache()

        var body: some View {
            let card = WhereStylesheet.default.card.regular
            if let style = card.regionShape?.securityBorder {
                RegionOutlineSecurityBorder(
                    paths: [path],
                    tint: .orange,
                    cornerRadius: card.cornerRadius,
                    inset: style.inset,
                    glyphSize: style.glyphSize,
                    spacing: style.spacing,
                    opacity: style.opacity,
                )
                .frame(width: 320, height: 180)
                .background(
                    .orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: card.cornerRadius),
                )
                .task {
                    path = await cache.path(for: .newYork, resolution: .micro)
                }
            }
        }
    }

    #Preview {
        RegionOutlineSecurityBorderPreview()
            .padding()
    }

#endif
