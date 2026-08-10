import SwiftUI

/// Draws paired shadows inside an arbitrary rendered subject's alpha mask.
/// Unlike a foreground shape style, this preserves the subject's own colors
/// and opacities, so composite ink such as the entry stamp can share the same
/// debossed lighting treatment as text.
struct TiltInsetShadow<Subject: View>: View {
    let subject: Subject
    let highlightColor: Color
    let shadowColor: Color
    let radius: CGFloat
    let highlightOffset: CGSize
    let shadowOffset: CGSize

    var body: some View {
        Canvas { context, size in
            guard let subject = context.resolveSymbol(id: SymbolID.subject) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            context.drawLayer { layer in
                layer.addFilter(.shadow(
                    color: highlightColor,
                    radius: radius,
                    x: highlightOffset.width,
                    y: highlightOffset.height,
                    options: .shadowOnly,
                ))
                layer.draw(subject, at: center)
            }
            context.drawLayer { layer in
                layer.addFilter(.shadow(
                    color: shadowColor,
                    radius: radius,
                    x: shadowOffset.width,
                    y: shadowOffset.height,
                    options: .shadowOnly,
                ))
                layer.draw(subject, at: center)
            }
        } symbols: {
            subject.tag(SymbolID.subject)
        }
        .mask(subject)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private enum SymbolID: Hashable {
        case subject
    }
}
