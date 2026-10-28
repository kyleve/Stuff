import SwiftUI

/// Inks planning controls into the forecast visa while preserving Button and
/// Menu semantics, minimum hit size, and native focus behavior.
struct LocationForecastEndorsementButtonStyle: ButtonStyle {
    let tint: Color
    let expands: Bool
    let controls: WhereStylesheet.LocationForecastStyle.Controls
    let ink: WhereStylesheet.LocationForecastStyle.Ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(controls.font)
            .foregroundStyle(tint)
            .padding(.horizontal, controls.horizontalPadding)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: controls.minimumHeight)
            .background {
                RoundedRectangle(cornerRadius: controls.cornerRadius)
                    .fill(tint.opacity(ink.controlFillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: controls.cornerRadius)
                    .strokeBorder(
                        tint.opacity(ink.controlStrokeOpacity),
                        lineWidth: controls.strokeWidth,
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: controls.cornerRadius))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
