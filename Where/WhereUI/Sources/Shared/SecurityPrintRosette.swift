import SwiftUI

/// Draws the layered concentric-ring security print shared by Where's passport
/// surfaces. Callers own the appearance values so each component can tune its
/// density without duplicating the guilloché renderer.
struct SecurityPrintRosette: View {
    let tint: Color
    let wobble: CGFloat
    let lineWidth: CGFloat
    let primaryRingSpacing: CGFloat
    let secondaryRingSpacing: CGFloat
    let primaryOpacity: Double
    let secondaryOpacity: Double

    var body: some View {
        Canvas { context, size in
            drawRosette(
                in: &context,
                size: size,
                center: CGPoint(x: size.width * 0.8, y: size.height * 0.5),
                spacing: primaryRingSpacing,
                opacity: primaryOpacity,
            )
            drawRosette(
                in: &context,
                size: size,
                center: CGPoint(x: size.width * 0.12, y: size.height * 0.22),
                spacing: secondaryRingSpacing,
                opacity: secondaryOpacity,
            )
        }
        .accessibilityHidden(true)
    }

    private func drawRosette(
        in context: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        spacing: CGFloat,
        opacity: Double,
    ) {
        let ringCount = Int(max(size.width, size.height) / spacing)
        for ring in 1 ... max(1, ringCount) {
            let angle = Double(ring) * 0.55
            let ringCenter = CGPoint(
                x: center.x + CGFloat(cos(angle)) * wobble,
                y: center.y + CGFloat(sin(angle)) * wobble,
            )
            let radius = CGFloat(ring) * spacing
            let rect = CGRect(
                x: ringCenter.x - radius,
                y: ringCenter.y - radius,
                width: radius * 2,
                height: radius * 2,
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(tint.opacity(opacity)),
                lineWidth: lineWidth,
            )
        }
    }
}

#if DEBUG
    #Preview {
        let rosette = WhereStylesheet.default.passportCard.rosette
        SecurityPrintRosette(
            tint: .accentColor,
            wobble: rosette.wobble,
            lineWidth: rosette.lineWidth,
            primaryRingSpacing: rosette.primaryRingSpacing,
            secondaryRingSpacing: rosette.secondaryRingSpacing,
            primaryOpacity: rosette.primaryOpacity,
            secondaryOpacity: rosette.secondaryOpacity,
        )
        .frame(width: 360, height: 120)
    }
#endif
