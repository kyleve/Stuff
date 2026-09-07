import SwiftUI

/// Diagonal lines distinguishing planned calendar presence from recorded days
/// without relying on color alone.
struct PlannedStayHatch: View {
    let color: Color
    let spacing: CGFloat
    let lineWidth: CGFloat
    /// This slice's horizontal origin in its enclosing grid. It keeps every
    /// slice on one stripe lattice instead of restarting the pattern per cell.
    let gridOriginX: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = Self.firstLineX(
                height: size.height,
                gridOriginX: gridOriginX,
                spacing: spacing,
            )
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }

    /// Starts far enough off-canvas to cover the top-leading corner while
    /// cancelling the slice's grid offset from the pattern phase.
    static func firstLineX(
        height: CGFloat,
        gridOriginX: CGFloat,
        spacing: CGFloat,
    ) -> CGFloat {
        -height - gridOriginX.truncatingRemainder(dividingBy: spacing)
    }
}

#if DEBUG
    #Preview {
        PlannedStayHatch(color: .indigo, spacing: 6, lineWidth: 1, gridOriginX: 0)
            .frame(width: 240, height: 80)
            .background(.indigo.opacity(0.08))
            .clipShape(.rect(cornerRadius: 16))
            .padding()
    }
#endif
