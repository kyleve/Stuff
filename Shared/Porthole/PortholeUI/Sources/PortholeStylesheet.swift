import SwiftUI
#if canImport(UIKit)
    import BroadwayCore
    import BroadwayUI
#endif

struct PortholeStylesheet {
    struct Row: Equatable {
        var spacing: CGFloat = 8
        var padding: CGFloat = 12
    }

    struct Code: Equatable {
        var font: Font = .system(.footnote, design: .monospaced)
        var minimumHeight: CGFloat = 180
    }

    struct Hosting: Equatable {
        var invitationSize: CGFloat = 240
    }

    var row = Row()
    var code = Code()
    var hosting = Hosting()

    init() {}

    #if canImport(UIKit)
        init(context: SlicingContext) throws {
            if context.traits.contentSizeCategory.isAccessibilitySize {
                row.spacing = 12
                code.minimumHeight = 240
            }
        }
    #endif

    static let `default` = PortholeStylesheet()
}

#if canImport(UIKit)
    extension PortholeStylesheet: BStylesheet {}

    extension EnvironmentValues {
        var portholeStylesheet: PortholeStylesheet {
            bContext.stylesheet(PortholeStylesheet.self, fallback: .default)
        }
    }

    extension View {
        func portholeBroadwayRoot() -> some View {
            broadwayRoot(themes: BThemes())
        }
    }
#else
    extension EnvironmentValues {
        @Entry var portholeStylesheet = PortholeStylesheet.default
    }

    private struct PortholeMacStyles: ViewModifier {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        func body(content: Content) -> some View {
            var stylesheet = PortholeStylesheet.default
            if dynamicTypeSize.isAccessibilitySize {
                stylesheet.row.spacing = 12
                stylesheet.code.minimumHeight = 240
            }
            return content.environment(\.portholeStylesheet, stylesheet)
        }
    }

    extension View {
        func portholeBroadwayRoot() -> some View {
            modifier(PortholeMacStyles())
        }
    }
#endif
