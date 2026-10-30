import BroadwayCore
import BroadwayUI
import SwiftUI

enum BTraitOverridesTestSupport {
    enum Theme: String, BTheme {
        static let defaultValue: Self = .a
        case a, b
    }

    @MainActor
    final class Reads {
        var latest: Values?
    }

    struct Values: Equatable {
        let colorScheme: ColorScheme
        let dynamicTypeSize: DynamicTypeSize
        let mode: BMode
        let contentSizeCategory: BContentSizeCategory
        let theme: Theme
    }

    struct Probe: View {
        let reads: Reads
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.bContext) private var context

        var body: some View {
            Color.clear.onChange(of: values, initial: true) { _, values in
                reads.latest = values
            }
        }

        private var values: Values {
            Values(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                mode: context.traits.mode,
                contentSizeCategory: context.traits.contentSizeCategory,
                theme: context.themes[Theme.self],
            )
        }
    }
}
