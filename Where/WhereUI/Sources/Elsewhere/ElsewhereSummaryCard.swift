import BroadwayUI
import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// A quiet passport card linking to the secondary regions. The caller owns
/// navigation; the count, border, and watermarks share the same ordered input.
struct ElsewhereSummaryCard: View {
    let regions: [Region]

    @Environment(\.stylesheet) private var stylesheet
    @State private var artworkModel = RegionArtworkModel<[Region], ElsewhereRegionArtwork>()

    private var style: WhereStylesheet.ElsewhereCardStyle {
        stylesheet.elsewhereCard
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }

    private var visibleArtwork: [ElsewhereRegionArtwork.Item] {
        artworkModel.artwork(for: regions)?.items(for: regions) ?? []
    }

    var body: some View {
        Group {
            if style.stacksContent {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    title
                    HStack(spacing: stylesheet.spacing.large) {
                        subtitle
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            } else {
                HStack(spacing: stylesheet.spacing.large) {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                        title
                        subtitle
                    }
                    Spacer(minLength: 0)
                    chevron
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(style.padding)
        .frame(maxWidth: .infinity, minHeight: style.minimumHeight, alignment: .leading)
        .background { securityPrint }
        .background {
            if style.surface.usesOpaquePaper {
                shape.fill(style.surface.paper)
            } else {
                shape.fill(.clear)
                    .glassEffect(
                        .regular.tint(style.surface.ink.opacity(style.surface.glassTintOpacity))
                            .interactive(),
                        in: shape,
                    )
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .shadow(
            color: .black.opacity(style.surface.shadowOpacity),
            radius: style.surface.shadowRadius,
            y: style.surface.shadowOffsetY,
        )
        .accessibilityElement(children: .combine)
        .regionArtworkTask(id: regions, model: artworkModel) { cache in
            await ElsewhereRegionArtwork.load(regions: regions, cache: cache)
        }
    }

    private var title: some View {
        Text(String(localized: .secondaryTitle))
            .font(style.titleFont)
            .foregroundStyle(.primary)
    }

    private var subtitle: some View {
        Text(WhereFormat.elsewhereCardSubtitle(regions: regions.count))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var chevron: some View {
        Image(systemSymbol: .chevronRight)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var securityPrint: some View {
        let paper = style.surface
        let border = style.border
        return ZStack {
            SecurityPrintRosette(
                tint: paper.ink,
                wobble: paper.rosette.wobble,
                lineWidth: paper.rosette.lineWidth,
                primaryRingSpacing: paper.rosette.primaryRingSpacing,
                secondaryRingSpacing: paper.rosette.secondaryRingSpacing,
                primaryOpacity: paper.rosetteOpacity,
                secondaryOpacity: paper.rosetteOpacity,
            )
            RegionOutlineSecurityBorder(
                paths: visibleArtwork.map(\.microprint),
                tint: paper.ink,
                cornerRadius: style.cornerRadius,
                inset: border.inset,
                glyphSize: border.glyphSize,
                spacing: border.spacing,
                opacity: border.opacity,
            )
            silhouettes
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var silhouettes: some View {
        GeometryReader { proxy in
            let area = CGSize(
                width: max(
                    0,
                    proxy.size.width * style.artwork.widthFraction - style.artwork.inset * 2,
                ),
                height: max(0, proxy.size.height - style.artwork.inset * 2),
            )
            let items = visibleArtwork
            let frames = ElsewhereArtworkLayout.frames(
                count: items.count,
                in: area,
                gap: style.artwork.gap,
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    let item = items[index]
                    Group {
                        if item.region == .other {
                            Image(systemSymbol: .globeAmericas)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(style.surface.ink
                                    .opacity(style.artwork.silhouette.stroke?.opacity ?? 0))
                        } else {
                            RegionOutlineArtwork(
                                path: item.watermark,
                                tint: style.surface.ink,
                                style: style.artwork.silhouette,
                            )
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(width: area.width, height: area.height)
            .mask {
                LinearGradient(
                    colors: [.black.opacity(style.artwork.leadingOpacity), .black],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
            }
            .position(
                x: proxy.size.width - style.artwork.inset - area.width / 2,
                y: proxy.size.height / 2,
            )
        }
    }
}

#if DEBUG
    import SnapshotKit

    extension ElsewhereSummaryCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            artworkSnapshot(
                name: "Several",
                regions: [.canada, .europeanUnion, .other],
                configurations: .componentDefaults,
            )
            artworkSnapshot(name: "One", regions: [.canada], configurations: .componentLightDark)
            artworkSnapshot(
                name: "Many",
                regions: Array(Region.allCases.prefix(20)),
                configurations: .componentLightDark,
            )
            artworkSnapshot(name: "Other", regions: [.other], configurations: .componentLightDark)
            artworkSnapshot(
                name: "ReduceTransparency",
                regions: [.canada, .europeanUnion, .other],
                configurations: .componentLightDark,
                reduceTransparency: true,
            )
        }

        private static func artworkSnapshot(
            name: String,
            regions: [Region],
            configurations: [SnapshotConfiguration],
            reduceTransparency: Bool = false,
        ) -> SnapshotCase {
            let cache = RegionOutlinePathCache()
            return whereSnapshot(
                name: name,
                configurations: configurations,
                measurementReadiness: .immediate,
                onReadyToSnapshot: {
                    _ = await ElsewhereRegionArtwork.load(regions: regions, cache: cache)
                },
            ) {
                snapshotCard(regions: regions)
                    .environment(\.regionOutlinePathCache, cache)
                    .bTraitOverrides { traits, overrides in
                        var accessibility = traits.accessibility
                        accessibility.isReduceTransparencyEnabled = reduceTransparency
                        overrides.accessibility = accessibility
                    }
            }
        }

        private static func snapshotCard(regions: [Region]) -> some View {
            ElsewhereSummaryCard(regions: regions)
                .padding()
                .background(Color(uiColor: .systemBackground))
        }
    }

    #Preview {
        ElsewhereSummaryCard.snapshotPreviews
    }
#endif
