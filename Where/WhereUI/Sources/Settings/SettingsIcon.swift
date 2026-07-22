import SwiftUI

/// The colored rounded-square icon chip for a top-level settings row (iOS-Settings
/// style): an SF Symbol centered on a per-section color. The glyph is white in
/// light mode and black in dark mode; the chip geometry comes from
/// `WhereStylesheet.SettingsStyle`.
struct SettingsIcon: View {
    let systemImage: String
    let color: Color

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let settings = stylesheet.settings
        Image(systemName: systemImage)
            .font(.system(size: settings.iconSymbolSize, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(width: settings.iconSize, height: settings.iconSize)
            .background(
                color,
                in: RoundedRectangle(cornerRadius: settings.iconCornerRadius, style: .continuous),
            )
            // Decorative: the row's text carries the accessibility label.
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        List {
            ForEach(SettingsDestination.allCases, id: \.self) { destination in
                Label {
                    Text(destination.rowTitle)
                } icon: {
                    SettingsIcon(systemImage: destination.systemImage, color: destination.iconColor)
                }
            }
        }
        .whereBroadwayRoot()
    }
#endif
