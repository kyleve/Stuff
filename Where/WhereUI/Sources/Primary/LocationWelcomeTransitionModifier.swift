import SwiftUI

/// Moves the complete welcome card like a stamp approaching or lifting from paper.
struct LocationWelcomeTransitionModifier: ViewModifier {
    let scale: CGFloat
    let rotationDegrees: Double
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotationDegrees))
            .offset(y: verticalOffset)
    }
}
