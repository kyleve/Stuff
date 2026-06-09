import SwiftUI

/// The shared chrome for one page of the passport booklet: a subtle paper
/// surface with a stitched binding seam along the leading edge, a couple of
/// page edges peeking out behind, and a serif "P. 02 / 03" footer.
struct PassportPage<Content: View>: View {
    let pageNumber: Int
    let pageCount: Int
    @ViewBuilder let content: Content

    private var pageShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: UIConstants.CornerRadius.passportPage,
            style: .continuous,
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacings.large) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(Strings.passportPageFooter(page: pageNumber, count: pageCount))
                .font(.system(.caption, design: .serif).weight(.medium))
                .tracking(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(
                    Strings.passportPageAccessibility(page: pageNumber, count: pageCount),
                )
        }
        .padding(UIConstants.Padding.passportPage)
        .background { paperStack }
        // Each booklet page is a discrete container so VoiceOver moves
        // through the booklet page by page, footer included.
        .accessibilityElement(children: .contain)
    }

    /// The page surface plus the edges of the "pages behind" it, offset
    /// toward the trailing corner so the booklet reads as having depth.
    private var paperStack: some View {
        ZStack {
            ForEach(1 ... UIConstants.Booklet.pageEdgeCount, id: \.self) { index in
                pageShape
                    .fill(.white.opacity(0.03))
                    .overlay { pageShape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
                    .offset(
                        x: CGFloat(index) * UIConstants.Booklet.pageEdgeOffsetX,
                        y: CGFloat(index) * UIConstants.Booklet.pageEdgeOffsetY,
                    )
            }

            pageShape
                .fill(Color(red: 0.10, green: 0.10, blue: 0.15))
                .overlay { paperGrain }
                .overlay { pageShape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                .overlay(alignment: .leading) { bindingSeam }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A faint, deterministic speckle wash that makes the page surface read
    /// as paper stock instead of a flat fill. Seeded so it doesn't shimmer
    /// across redraws.
    private var paperGrain: some View {
        Canvas { context, size in
            var rng = SplitMix64(seed: 0x9E37_79B9_7F4A_7C15)
            let speckles = Int(size.width * size.height / UIConstants.Booklet.grainAreaPerSpeckle)
            for _ in 0 ..< max(0, speckles) {
                let origin = CGPoint(
                    x: CGFloat.random(in: 0 ..< size.width, using: &rng),
                    y: CGFloat.random(in: 0 ..< size.height, using: &rng),
                )
                let alpha = Double.random(in: 0.3 ... 1, using: &rng)
                context.fill(
                    Path(CGRect(origin: origin, size: CGSize(width: 1, height: 1))),
                    with: .color(.white.opacity(alpha)),
                )
            }
        }
        .opacity(UIConstants.Booklet.grainOpacity)
        .blendMode(.overlay)
        .clipShape(pageShape)
    }

    /// A dashed vertical line just inside the leading edge — the stitching
    /// where the page is sewn into the booklet's spine.
    private var bindingSeam: some View {
        VerticalLine()
            .stroke(
                GoldFoil.solid.opacity(0.35),
                style: StrokeStyle(
                    lineWidth: UIConstants.Booklet.bindingSeamLineWidth,
                    lineCap: .round,
                    dash: [
                        UIConstants.Booklet.bindingSeamDashLength,
                        UIConstants.Booklet.bindingSeamDashLength,
                    ],
                ),
            )
            .frame(width: UIConstants.Booklet.bindingSeamLineWidth)
            .padding(.vertical, UIConstants.Spacings.xxLarge)
            .padding(.leading, UIConstants.Spacings.large)
    }
}

/// A straight vertical line through the middle of its rect, for dashed
/// stroking (a plain `Rectangle` would dash its outline instead).
private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// A tiny seedable PRNG (SplitMix64) so the paper grain is stable across
/// redraws — `SystemRandomNumberGenerator` can't be seeded.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09).ignoresSafeArea()
            PassportPage(pageNumber: 2, pageCount: 3) {
                Text(verbatim: "Page content")
            }
            .padding()
            .environment(\.colorScheme, .dark)
        }
    }
#endif
