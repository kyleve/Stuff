import RegionKit
import SwiftUI

/// Quiet passport print loaded through the same root-owned cache as Locations.
struct OnboardingBackground: View {
    var regions: [Region] = [.california, .newYork]
    @Environment(\.stylesheet) private var stylesheet
    @State private var artwork = RegionArtworkModel<[Region], [Path]>()

    var body: some View {
        let style = stylesheet.onboarding
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if style.showsArtwork {
                SecurityPrintRosette(
                    tint: .primary,
                    wobble: style.rosette.wobble,
                    lineWidth: style.rosette.lineWidth,
                    primaryRingSpacing: style.rosette.primaryRingSpacing,
                    secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                    primaryOpacity: style.rosetteOpacity,
                    secondaryOpacity: style.rosetteOpacity,
                )
                if let paths = artwork.artwork(for: regions) {
                    HStack {
                        ForEach(paths.indices, id: \.self) { index in
                            RegionOutlineArtwork(
                                path: paths[index],
                                tint: .primary,
                                style: style.outline,
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .regionArtworkTask(id: regions, model: artwork) { cache in
            var paths: [Path] = []
            for region in regions {
                await paths.append(cache.path(for: region, resolution: .medium))
            }
            return paths
        }
    }
}

#if DEBUG
    #Preview { OnboardingBackground().whereBroadwayRoot() }
#endif
