import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Editor for one region's look: color, emoji, and icon grids picked from the
/// predefined `RegionAppearanceCatalog`, above a live `RegionSummaryCard`
/// preview that reflects the in-progress appearance. The caller owns the draft.
struct RegionAppearanceEditor: WhereScreen {
    let region: Region
    @Binding var appearance: RegionAppearance

    /// Matches the Locations card's live sheen response while this editor is
    /// visible; the card uses its static pose until the first sample arrives.
    @State private var tilt = TiltProvider()

    @Environment(\.stylesheet) private var stylesheet

    var contentPadding: WhereContentPadding {
        .none
    }

    var content: some View {
        VStack(spacing: stylesheet.spacing.xLarge) {
            RegionAppearanceCardPreview(region: region, appearance: appearance, tilt: tilt)

            RegionAppearanceSection(title: String(localized: .regionCustomizeColor)) {
                RegionColorChoices(appearance: $appearance)
            }
            RegionAppearanceSection(title: String(localized: .regionCustomizeEmoji)) {
                RegionEmojiChoices(appearance: $appearance)
            }
            RegionAppearanceSection(title: String(localized: .regionCustomizeSymbol)) {
                RegionSymbolChoices(appearance: $appearance)
            }
        }
        .padding(stylesheet.spacing.large)
        .observesTilt(tilt, enabled: stylesheet.card.regular.surface.usesReflection)
    }
}

private struct RegionAppearanceCardPreview: View {
    @Environment(\.stylesheet) private var stylesheet
    let region: Region
    let appearance: RegionAppearance
    let tilt: TiltProvider

    var body: some View {
        GlassEffectContainer(spacing: stylesheet.spacing.xxLarge) {
            RegionSummaryCard(
                regionDays: RegionDays(region: region, days: 128),
                caption: WhereFormat.regionCustomizeSubtitle(region: region.localizedName),
                tilt: tilt,
                styleOverride: RegionStyle(appearance),
            )
        }
        .animation(stylesheet.motion.captionFade, value: appearance)
    }
}

private struct RegionAppearanceSection<Content: View>: View {
    @Environment(\.stylesheet) private var stylesheet
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlyphSelectionBackground: View {
    let isSelected: Bool
    let style: WhereStylesheet.RegionPickerStyle

    var body: some View {
        RoundedRectangle(cornerRadius: style.glyphCornerRadius, style: .continuous)
            .fill(isSelected
                ? Color.accentColor.opacity(style.glyphSelectedBackgroundOpacity)
                : Color(.secondarySystemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: style.glyphCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        lineWidth: isSelected ? style.glyphSelectionStrokeWidth : 0,
                    )
            }
    }
}

private struct RegionColorChoices: View {
    @Environment(\.stylesheet) private var stylesheet
    @Binding var appearance: RegionAppearance

    private var style: WhereStylesheet.RegionPickerStyle {
        stylesheet.regionPicker
    }

    private var colorColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: style.colorSwatchMinWidth),
            spacing: stylesheet.spacing.medium,
        )]
    }

    var body: some View {
        LazyVGrid(columns: colorColumns, spacing: stylesheet.spacing.medium) {
            ForEach(RegionAppearanceCatalog.colors, id: \.self) { token in
                RegionColorButton(appearance: $appearance, token: token, style: style)
            }
        }
    }
}

private struct RegionEmojiButton: View {
    @Binding var appearance: RegionAppearance
    let emoji: String
    let style: WhereStylesheet.RegionPickerStyle

    var body: some View {
        let isSelected = appearance.emoji == emoji
        Button {
            appearance.emoji = emoji
        } label: {
            Text(emoji)
                .font(.title2)
                .frame(width: style.glyphTileSize, height: style.glyphTileSize)
                .background(GlyphSelectionBackground(isSelected: isSelected, style: style))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct RegionEmojiChoices: View {
    @Environment(\.stylesheet) private var stylesheet
    @Binding var appearance: RegionAppearance

    private var style: WhereStylesheet.RegionPickerStyle {
        stylesheet.regionPicker
    }

    private var glyphColumns: [GridItem] {
        [GridItem(.adaptive(minimum: style.glyphTileMinWidth), spacing: stylesheet.spacing.small)]
    }

    var body: some View {
        LazyVGrid(columns: glyphColumns, spacing: stylesheet.spacing.small) {
            ForEach(RegionAppearanceCatalog.emojis, id: \.self) { emoji in
                RegionEmojiButton(appearance: $appearance, emoji: emoji, style: style)
            }
        }
    }
}

private struct RegionSymbolButton: View {
    @Binding var appearance: RegionAppearance
    let symbol: RegionSymbol
    let style: WhereStylesheet.RegionPickerStyle

    var body: some View {
        let isSelected = appearance.symbolName == symbol
        Button {
            appearance.symbolName = symbol
        } label: {
            Image(systemSymbol: symbol.sfSymbol)
                .font(.title3)
                .foregroundStyle(appearance.color.color)
                .frame(width: style.glyphTileSize, height: style.glyphTileSize)
                .background(GlyphSelectionBackground(isSelected: isSelected, style: style))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct RegionSymbolChoices: View {
    @Environment(\.stylesheet) private var stylesheet
    @Binding var appearance: RegionAppearance

    private var style: WhereStylesheet.RegionPickerStyle {
        stylesheet.regionPicker
    }

    private var glyphColumns: [GridItem] {
        [GridItem(.adaptive(minimum: style.glyphTileMinWidth), spacing: stylesheet.spacing.small)]
    }

    var body: some View {
        LazyVGrid(columns: glyphColumns, spacing: stylesheet.spacing.small) {
            ForEach(RegionAppearanceCatalog.symbols, id: \.self) { symbol in
                RegionSymbolButton(appearance: $appearance, symbol: symbol, style: style)
            }
        }
    }
}

#if DEBUG
    #Preview("Editor") {
        @Previewable @Bindable var draft = PreviewSupport.primaryRegionDraft()
        RegionAppearanceEditor(region: .california, appearance: $draft[appearanceFor: .california])
            .whereBroadwayRoot()
    }

#endif
