import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct SnapshotHostingControllerTests {
    @Test func previewAndCaptureResolveTheSameNativeTraitsWithAndWithoutAUIKitOverride() throws {
        let previewReads = SnapshotHostingControllerTestSupport.Reads()
        let captureReads = SnapshotHostingControllerTestSupport.Reads()
        let configurations = [
            SnapshotConfiguration(
                colorScheme: .dark,
                dynamicType: .accessibility3,
                contrast: .increased,
                layoutDirection: .rightToLeft,
                legibilityWeight: .bold,
                layoutTraits: .tabletPortrait,
            ),
            SnapshotConfiguration(),
        ]
        func preview(configuration: SnapshotConfiguration) -> some View {
            SnapshotHostingControllerTestSupport.Probe(reads: previewReads)
                .snapshotTraits(configuration)
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(.accessibility5)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.legibilityWeight, .bold)
        }
        let host = UIHostingController(rootView: preview(configuration: configurations[0]))
        try show(host) { _ in
            for configuration in configurations {
                host.rootView = preview(configuration: configuration)
                try waitFor {
                    previewReads.latest?.colorScheme == configuration.colorScheme
                        && previewReads.latest?.dynamicTypeSize == configuration.dynamicType
                        && previewReads.latest?.layoutDirection == configuration.layoutDirection
                        && previewReads.latest?.legibilityWeight == configuration.legibilityWeight
                }
            }
        }

        for configuration in configurations {
            captureReads.latest = nil
            let captureHost = makeHostingController(
                for: SnapshotHostingControllerTestSupport.Probe(reads: captureReads),
                configuration: configuration,
            )
            try show(captureHost) { _ in
                try waitFor {
                    captureReads.latest?.colorScheme == configuration.colorScheme
                        && captureReads.latest?.dynamicTypeSize == configuration.dynamicType
                        && captureReads.latest?.layoutDirection == configuration.layoutDirection
                        && captureReads.latest?.legibilityWeight == configuration.legibilityWeight
                }
            }
        }
    }
}
