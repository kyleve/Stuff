import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WidgetKit

/// History-free widget recovery. Opening the app supplies the specific update/verification action.
public struct WidgetCompatibilityView: View {
    private let family: WidgetFamily
    @Environment(\.stylesheet) private var stylesheet

    public init(family: WidgetFamily) {
        self.family = family
    }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.widgetCompatibilityTitle))
            .accessibilityValue(Text(.widgetCompatibilityMessage))
            .containerBackground(for: .widget) {
                switch family {
                    case .accessoryInline, .accessoryCircular, .accessoryRectangular,
                         .accessoryCorner:
                        Color.clear
                    case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                         .systemExtraLargePortrait:
                        Rectangle().fill(.background)
                    @unknown default:
                        Rectangle().fill(.background)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
            case .accessoryInline:
                Label(String(localized: .widgetCompatibilityTitle), systemSymbol: .lock)
            case .accessoryCircular, .accessoryCorner:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemSymbol: .lock).font(.title3)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                    Label(String(localized: .widgetCompatibilityTitle), systemSymbol: .lock)
                        .font(.caption.weight(.semibold))
                    Text(.widgetCompatibilityMessage).font(.caption2)
                }
            case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                 .systemExtraLargePortrait:
                homeContent
            @unknown default:
                homeContent
        }
    }

    private var homeContent: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: stylesheet.spacing.small) {
                Image(systemSymbol: .lock).font(.title3).foregroundStyle(.secondary)
                VStack(spacing: stylesheet.spacing.xSmall) {
                    Text(.widgetCompatibilityTitle).font(.headline)
                    Text(.widgetCompatibilityMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(.widgetCompatibilityTitle)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
    extension WidgetCompatibilityView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            // Home widgets exercise both themes and the compact large-type fallback. Accessories
            // keep native monochrome styling, so their distinct shapes need only one theme.
            whereThemeSnapshot(
                name: "Home",
                configurations: .componentLightDark + [.init(dynamicType: .accessibility5)],
                settle: .immediate,
            ) {
                Self(family: .systemSmall).frame(width: 150, height: 150).background(.background)
            }
            whereSnapshot(name: "Inline", configurations: .componentLightDark, settle: .immediate) {
                Self(family: .accessoryInline).frame(width: 180, height: 26).background(.background)
            }
            whereSnapshot(
                name: "Circular",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                Self(family: .accessoryCircular).frame(width: 76, height: 76)
                    .background(.background)
            }
            whereSnapshot(
                name: "Rectangular",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                Self(family: .accessoryRectangular).frame(width: 180, height: 76)
                    .background(.background)
            }
        }
    }

    extension WidgetCompatibilityView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            Self.self,
            title: "Widget Compatibility",
            viewport: .fixed(CGSize(width: 180, height: 180)),
            navigationContainer: .none,
        )
    }

    #Preview { WidgetCompatibilityView.snapshotPreviews }
#endif
