import Foundation
@testable import PeriscopeTools
import SwiftUI
import Testing

@MainActor
enum PeriscopeToolPresentationTestSupport {
    struct Defaults {
        let suite: String
        let value: UserDefaults

        init() throws {
            suite = "periscope.presentation.tests.\(UUID().uuidString)"
            value = try #require(UserDefaults(suiteName: suite))
        }

        func cleanup() {
            value.removePersistentDomain(forName: suite)
        }
    }

    final class Reads {
        var density: PeriscopeStylesheet.Density?
    }

    struct Probe: View {
        let reads: Reads
        @Environment(\.logRowDensity) private var density

        var body: some View {
            Color.clear.onChange(of: density, initial: true) { _, value in
                reads.density = value
            }
        }
    }
}
