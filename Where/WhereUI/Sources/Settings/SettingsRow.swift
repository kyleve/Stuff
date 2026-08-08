import SwiftUI
import UIKit

/// Opens the system Settings app, shared by the settings sub-screens that guide
/// the user there (location permission, notification permission).
@MainActor
func openSystemSettings(_ openURL: OpenURLAction) {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    openURL(url)
}

extension EnvironmentValues {
    /// The setting a search deep-link is currently flashing, injected by
    /// ``SettingsFocusScope`` and read by ``SettingsRowModifier`` so the matching
    /// row tints briefly. `nil` when nothing is highlighted.
    @Entry var settingsHighlight: SettingsFocus?
}

extension View {
    /// Tags a settings row with its ``SettingsItem`` so a search deep-link can
    /// scroll to it and flash it. Applies `.id(SettingsFocus(item))` (the scroll
    /// address) and a flash background driven by `\.settingsHighlight`. Taking
    /// `some SettingsItem` means a row can't be tagged with a non-item value.
    func settingsRow(
        _ item: some SettingsItem,
        restingBackground: SettingsRowRestingBackground = .grouped,
    ) -> some View {
        modifier(SettingsRowModifier(
            focus: SettingsFocus(item),
            restingBackground: restingBackground,
        ))
    }
}

enum SettingsRowRestingBackground: Equatable {
    case grouped
    case clear

    var color: Color {
        switch self {
            case .grouped: Color(.secondarySystemGroupedBackground)
            case .clear: .clear
        }
    }
}

/// Applies the scroll id + flash background for a tagged settings row. The flash
/// tint (accent) and the restored grouped-row background (a system role) stay
/// inline here, not in the stylesheet, per the "no adaptive/accent colors in the
/// sheet" rule.
struct SettingsRowModifier: ViewModifier {
    let focus: SettingsFocus
    let restingBackground: SettingsRowRestingBackground

    @Environment(\.settingsHighlight) private var highlight

    private var isHighlighted: Bool {
        highlight == focus
    }

    func body(content: Content) -> some View {
        content
            .id(focus)
            .listRowBackground(background)
            .overlay {
                if restingBackground == .clear {
                    Color.accentColor
                        .opacity(isHighlighted ? 0.25 : 0)
                        .allowsHitTesting(false)
                }
            }
    }

    private var background: some View {
        // Ordinary settings rows keep the system grouped fill; marketing rows
        // opt into clear so their page background can show through.
        isHighlighted ? Color.accentColor.opacity(0.25) : restingBackground.color
    }
}

/// Wraps a settings sub-screen's scrollable content so a search deep-link can
/// scroll a focused row into view and flash it. Owns the highlight state, injects
/// it into the environment for ``SettingsRowModifier``, and honors Reduce Motion
/// (no fade — still scrolls and shows a brief static highlight). Flashes once per
/// appearance so returning to the screen doesn't re-flash.
struct SettingsFocusScope<Content: View>: View {
    let focus: SettingsFocus?
    let content: Content

    @State private var highlighted: SettingsFocus?
    @State private var didReveal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stylesheet) private var stylesheet

    init(focus: SettingsFocus?, @ViewBuilder content: () -> Content) {
        self.focus = focus
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .environment(\.settingsHighlight, highlighted)
                .task {
                    guard !didReveal else { return }
                    didReveal = true
                    await reveal(using: proxy)
                }
        }
    }

    private func reveal(using proxy: ScrollViewProxy) async {
        guard let focus else { return }
        let settings = stylesheet.settings
        // Let the push settle so the row is laid out before we scroll to it.
        try? await Task.sleep(for: settings.scrollSettleDelay)
        guard !Task.isCancelled else { return }

        let animation = reduceMotion ? nil : settings.flashAnimation
        withAnimation(animation) {
            proxy.scrollTo(focus, anchor: .center)
            highlighted = focus
        }

        try? await Task.sleep(for: settings.flashDuration)
        guard !Task.isCancelled else { return }
        withAnimation(animation) { highlighted = nil }
    }
}

#if DEBUG
    #Preview {
        SettingsFocusScope(focus: SettingsFocus(LocationSettingsView.Item.tracking)) {
            List {
                Label(
                    String(localized: .settingsLocationToggle),
                    systemImage: "location.fill",
                )
                .settingsRow(LocationSettingsView.Item.tracking)
            }
        }
        .whereBroadwayRoot()
    }
#endif
