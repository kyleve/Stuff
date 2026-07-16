import RegionKit
import SwiftUI
import WhereCore

/// Editor for one region's look: color, emoji, and icon grids picked from the
/// predefined `RegionAppearanceCatalog`, above a live `RegionSummaryCard`
/// preview that reflects the in-progress draft. Writes straight into the shared
/// ``PrimaryRegionSelectionModel`` draft; reused by the onboarding stepping flow
/// and the Settings editor.
struct RegionAppearanceEditor: View {
    @Bindable var model: PrimaryRegionSelectionModel
    let region: Region

    @Environment(\.stylesheet) private var stylesheet

    private var appearance: RegionAppearance {
        model.appearance(for: region)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: stylesheet.spacing.xLarge) {
                preview

                section(Strings.regionCustomizeColor) {
                    colorGrid
                }
                section(Strings.regionCustomizeEmoji) {
                    emojiGrid
                }
                section(Strings.regionCustomizeSymbol) {
                    symbolGrid
                }
            }
            .padding(stylesheet.spacing.large)
        }
    }

    private var preview: some View {
        RegionSummaryCard(
            regionDays: RegionDays(region: region, days: 128),
            caption: Strings.regionCustomizeSubtitle(region: region.localizedName),
            styleOverride: RegionStyle(appearance),
        )
        .animation(stylesheet.motion.captionFade, value: appearance)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var style: WhereStylesheet.RegionPickerStyle {
        stylesheet.regionPicker
    }

    private var colorColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: style.colorSwatchMinWidth),
            spacing: stylesheet.spacing.medium,
        )]
    }

    private var colorGrid: some View {
        LazyVGrid(columns: colorColumns, spacing: stylesheet.spacing.medium) {
            ForEach(RegionAppearanceCatalog.colors, id: \.self) { token in
                let isSelected = appearance.color == token
                Button {
                    model.setColor(token, for: region)
                } label: {
                    Circle()
                        .fill(token.color)
                        .frame(width: style.colorSwatchSize, height: style.colorSwatchSize)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    .primary,
                                    lineWidth: isSelected ? style.colorSwatchSelectionRing : 0,
                                )
                        }
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.regionColorAccessibility(token))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var glyphColumns: [GridItem] {
        [GridItem(.adaptive(minimum: style.glyphTileMinWidth), spacing: stylesheet.spacing.small)]
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: glyphColumns, spacing: stylesheet.spacing.small) {
            ForEach(RegionAppearanceCatalog.emojis, id: \.self) { emoji in
                let isSelected = appearance.emoji == emoji
                Button {
                    model.setEmoji(emoji, for: region)
                } label: {
                    Text(emoji)
                        .font(.title2)
                        .frame(width: style.glyphTileSize, height: style.glyphTileSize)
                        .background(selectionBackground(isSelected))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: glyphColumns, spacing: stylesheet.spacing.small) {
            ForEach(RegionAppearanceCatalog.symbols, id: \.self) { symbol in
                let isSelected = appearance.symbolName == symbol
                Button {
                    model.setSymbol(symbol, for: region)
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(appearance.color.color)
                        .frame(width: style.glyphTileSize, height: style.glyphTileSize)
                        .background(selectionBackground(isSelected))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func selectionBackground(_ isSelected: Bool) -> some View {
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

/// Steps through each picked region in pick order, editing its look with
/// ``RegionAppearanceEditor``. Back/Next (Done on the last region) live in the
/// navigation bar, so the caller must place this inside a `NavigationStack`.
/// `onFinish` fires when the user advances past the last region; `onBack` fires
/// when they go back before the first (so onboarding returns to the picker and
/// the Settings editor returns to its pick phase).
struct RegionCustomizeView: View {
    @Bindable var model: PrimaryRegionSelectionModel
    var onBack: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var index = 0

    @Environment(\.stylesheet) private var stylesheet

    private var regions: [Region] {
        model.selectedRegions
    }

    var body: some View {
        Group {
            if let region = currentRegion {
                RegionAppearanceEditor(model: model, region: region)
                    .id(region)
                    .transition(.opacity)
            } else {
                // No selection to customize — nothing to step through.
                ContentUnavailableView(
                    Strings.regionPickerTitle,
                    systemImage: "map",
                    description: Text(Strings.regionPickerSubtitle),
                )
            }
        }
        .animation(stylesheet.motion.captionFade, value: index)
        .navigationTitle(currentRegion?.localizedName ?? Strings.regionCustomizeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(Strings.onboardingBack, action: goBack)
            }
            ToolbarItem(placement: .principal) {
                Text(Strings.regionCustomizeStep(current: effectiveIndex + 1, total: regions.count))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isLast ? Strings.commonDone : Strings.onboardingNext, action: goNext)
            }
        }
    }

    /// `index` clamped into range, so a stale/out-of-range value can never
    /// strand the user — the empty state (`currentRegion == nil`) is reserved for
    /// a genuinely empty selection, which the current flow never reaches.
    private var effectiveIndex: Int {
        guard !regions.isEmpty else { return 0 }
        return min(max(index, 0), regions.count - 1)
    }

    private var currentRegion: Region? {
        regions.isEmpty ? nil : regions[effectiveIndex]
    }

    private var isLast: Bool {
        effectiveIndex >= regions.count - 1
    }

    private func goBack() {
        if effectiveIndex == 0 {
            onBack()
        } else {
            index = effectiveIndex - 1
        }
    }

    private func goNext() {
        if isLast {
            onFinish()
        } else {
            index = effectiveIndex + 1
        }
    }
}

#if DEBUG
    #Preview("Editor") {
        RegionAppearanceEditor(
            model: PreviewSupport.primaryRegionSelectionModel(),
            region: .california,
        )
        .whereBroadwayRoot()
    }

    #Preview("Stepping") {
        NavigationStack {
            RegionCustomizeView(model: PreviewSupport.primaryRegionSelectionModel())
        }
        .whereBroadwayRoot()
    }
#endif
