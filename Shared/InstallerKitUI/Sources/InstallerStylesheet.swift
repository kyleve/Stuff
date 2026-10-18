import BroadwayCore
import BroadwayUI
import SwiftUI

/// App Store-inspired presentation shared by every host, sliced before views interpret appearance.
struct InstallerStylesheet: BStylesheet {
    var page = Page()
    var hero = Hero()
    var card = Card()
    var summary = Summary()
    var details = Details()
    var changes = Changes()
    var check = Check()
    var browser = Browser()

    init() {}

    init(context: SlicingContext) throws {
        if context.traits.contentSizeCategory.isAccessibilitySize {
            hero.arrangement = .stacked
            details.arrangement = .stacked
            summary.columns = .single
        }
        hero.iconSize = BScaledDimension.value(
            hero.iconSize,
            relativeTo: .title2,
            category: context.traits.contentSizeCategory,
        )
    }

    static let `default` = InstallerStylesheet()

    enum Arrangement: Equatable { case horizontal, stacked }

    struct Page: Equatable {
        var background = Color(.systemGroupedBackground)
        var maximumWidth: CGFloat = 760
        var padding: CGFloat = 20
        var spacing: CGFloat = 20
    }

    struct Hero: Equatable {
        var arrangement = Arrangement.horizontal
        var spacing: CGFloat = 20
        var textSpacing: CGFloat = 10
        var iconSize: CGFloat = 100
        var iconCornerRatio: CGFloat = 0.2237
        var iconFill = Color(.secondarySystemGroupedBackground)
        var titleFont = Font.title2.bold()
        var subtitleFont = Font.subheadline
        var monogramFont = Font.largeTitle.bold()
        var badgeFont = Font.caption.weight(.semibold)
        var badgeHorizontalPadding: CGFloat = 10
        var badgeVerticalPadding: CGFloat = 5
        var badgeFill = Color.accentColor.opacity(0.1)
        var actionFont = Font.headline
        var actionHorizontalPadding: CGFloat = 22
        var actionMinimumHeight: CGFloat = 44
    }

    struct Card: Equatable {
        var background = Color(.secondarySystemGroupedBackground)
        var cornerRadius: CGFloat = 24
        var padding: CGFloat = 20
        var spacing: CGFloat = 16
        var titleFont = Font.title3.bold()
        var bodyFont = Font.subheadline
    }

    struct Summary: Equatable {
        enum Columns: Equatable { case adaptive, single }
        var columns = Columns.adaptive
        var minimumColumnWidth: CGFloat = 140
        var spacing: CGFloat = 20
        var itemSpacing: CGFloat = 6
        var labelFont = Font.caption2.weight(.semibold)
        var valueFont = Font.title3.weight(.semibold)
    }

    struct Details: Equatable {
        var arrangement = Arrangement.horizontal
        var revisionLength = 7
        var spacing: CGFloat = 8
        var valueFont = Font.subheadline.monospaced()
        var labelFont = Font.subheadline
    }

    struct Changes: Equatable {
        var revisionLength = 7
        var spacing: CGFloat = 8
        var titleFont = Font.body
        var revisionFont = Font.caption.monospaced()
        var arrowFont = Font.caption.weight(.semibold)
        var minimumHeight: CGFloat = 44
    }

    struct Check: Equatable {
        var font = Font.headline
        var minimumHeight: CGFloat = 44
    }

    struct Browser: Equatable {
        var spacing: CGFloat = 8
        var minimumHeight: CGFloat = 44
        var titleFont = Font.headline
        var metadataFont = Font.subheadline
        var revisionFont = Font.caption.monospaced()
        var badgeFont = Font.caption.weight(.semibold)
        var actionFont = Font.headline
        var arrowFont = Font.caption.weight(.semibold)
        var revisionLength = 7
    }
}

extension EnvironmentValues {
    var installerStylesheet: InstallerStylesheet {
        bContext.stylesheet(InstallerStylesheet.self, fallback: .default)
    }
}

extension View {
    func installerBroadwayRoot() -> some View {
        broadwayRoot(themes: BThemes())
    }
}
