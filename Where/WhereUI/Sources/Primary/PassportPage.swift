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
                .overlay { pageShape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
                .overlay(alignment: .leading) { bindingSeam }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
