import SwiftUI

/// Faint primary-region silhouettes, faded toward the summary's leading text.
struct LocationForecastSilhouettes: View {
    let artwork: [LocationForecastArtworkLoader.Item]

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let summary = stylesheet.locationForecast.summary
        let style = summary.artwork
        GeometryReader { proxy in
            let area = CGSize(
                width: max(0, proxy.size.width * style.widthFraction - style.inset * 2),
                height: max(0, proxy.size.height - style.inset * 2),
            )
            let frames = LocationForecastArtworkLayout.frames(
                count: artwork.count,
                in: area,
                gap: style.gap,
            )
            ZStack(alignment: .topLeading) {
                ForEach(artwork.enumerated(), id: \.element.id) { index, item in
                    if frames.indices.contains(index) {
                        let frame = frames[index]
                        RegionOutlineArtwork(
                            path: item.watermark,
                            tint: summary.ink,
                            style: style.silhouette,
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: area.width, height: area.height)
            .mask {
                LinearGradient(
                    colors: [.black.opacity(style.leadingOpacity), .black],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
            }
            .position(
                x: proxy.size.width - style.inset - area.width / 2,
                y: proxy.size.height / 2,
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        LocationForecastSummary.snapshotPreviews
    }
#endif
