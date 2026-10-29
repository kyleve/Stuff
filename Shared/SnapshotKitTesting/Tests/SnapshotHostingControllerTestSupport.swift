import SwiftUI

enum SnapshotHostingControllerTestSupport {
    @MainActor
    final class Reads {
        var latest: Values?
    }

    struct Values: Equatable {
        let colorScheme: ColorScheme
        let dynamicTypeSize: DynamicTypeSize
        let layoutDirection: LayoutDirection
        let legibilityWeight: LegibilityWeight?
    }

    struct Probe: View {
        let reads: Reads
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.layoutDirection) private var layoutDirection
        @Environment(\.legibilityWeight) private var legibilityWeight

        var body: some View {
            Color.clear
                .frame(width: 80, height: 80)
                .onChange(of: values, initial: true) { _, values in
                    reads.latest = values
                }
        }

        private var values: Values {
            Values(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                layoutDirection: layoutDirection,
                legibilityWeight: legibilityWeight,
            )
        }
    }
}
