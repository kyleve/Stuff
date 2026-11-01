import SwiftUI

/// Document-owned screen paint and typography leave navigation and controls native.
private struct WhereThemeScreen: ViewModifier {
    let role: WhereThemeComponents.Role
    @Environment(\.whereComponentStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet[role]
        if style.background != nil || !style.artworkOpacity.isEmpty || style.body != nil || style
            .foreground != nil
        {
            content
                .scrollContentBackground(.hidden)
                .font(style.body)
                .fontDesign(style.bodyDesign)
                .foregroundStyle(style.foreground ?? .primary)
                .environment(\.whereThemeSecondaryInk, style.secondaryForeground)
                .tint(style.foreground ?? .accentColor)
                .background {
                    (style.background ?? nativeBackground).ignoresSafeArea()
                        .overlay { WhereComponentArtwork(
                            role: role,
                            plane: .interior,
                            shape: Rectangle(),
                        ) }
                        .overlay { WhereComponentArtwork(
                            role: role,
                            plane: .exterior,
                            shape: Rectangle(),
                        ) }
                        .clipped()
                }
        } else {
            content
        }
    }

    private var nativeBackground: Color {
        switch role {
            case .settings, .sheet: Color(.systemGroupedBackground)
            case .locations, .elsewhere, .year, .regularCard, .compactCard, .elsewhereCard,
                 .summary,
                 .forecastPanel, .calendarMonth, .timelineEntry, .section, .welcome,
                 .privacy: Color(.systemBackground)
        }
    }
}

extension View {
    func whereThemeScreen(_ role: WhereThemeComponents.Role) -> some View {
        modifier(WhereThemeScreen(role: role))
    }
}
