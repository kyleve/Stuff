import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// The adaptive theme selector shared by onboarding and Appearance Settings.
/// Its specimens render production cards with each theme's resolved surface.
struct WhereThemePicker: View {
    let selection: WhereTheme
    let onSelect: (WhereTheme) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Group {
            if stylesheet.themePicker.layout == .stacked {
                stackedOptions
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: stylesheet.themePicker.spacing) {
                        WhereThemeOptions(selection: selection, onSelect: onSelect)
                    }
                    .frame(minWidth: stylesheet.themePicker.minimumInlineWidth)
                    stackedOptions
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var stackedOptions: some View {
        VStack(spacing: stylesheet.themePicker.spacing) { WhereThemeOptions(
            selection: selection,
            onSelect: onSelect,
        ) }
    }
}

private struct WhereThemeOptions: View {
    let selection: WhereTheme
    let onSelect: (WhereTheme) -> Void

    var body: some View {
        ForEach(WhereTheme.allCases, id: \.self) { theme in
            WhereThemeOptionButton(theme: theme, isSelected: theme == selection, onSelect: onSelect)
        }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var selection = WhereTheme.standard
        WhereThemePicker(selection: selection) { selection = $0 }
            .padding()
            .whereBroadwayRoot(theme: selection)
    }
#endif
