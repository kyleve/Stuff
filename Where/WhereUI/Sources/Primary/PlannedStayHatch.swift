import SwiftUI

/// Diagonal lines distinguishing planned calendar presence from recorded days
/// without relying on color alone.
struct PlannedStayHatch: View {
    let color: Color
    let spacing: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        PlannedStayHatch(color: .indigo, spacing: 6, lineWidth: 1)
            .frame(width: 240, height: 80)
            .background(.indigo.opacity(0.08))
            .clipShape(.rect(cornerRadius: 16))
            .padding()
    }
#endif
