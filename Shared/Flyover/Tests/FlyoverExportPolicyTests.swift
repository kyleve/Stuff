#if DEBUG
    @testable import Flyover
    import SnapshotKit
    import SwiftUI
    import Testing

    @MainActor
    struct FlyoverExportPolicyTests {
        @Test func emptySnapshotMatrixUsesViewportAndPreservesReadiness() {
            let snapshotCase = SnapshotCase(
                name: "Empty",
                configurations: [],
                measurementReadiness: .immediate,
                settle: .immediate,
            ) {
                EmptyView()
            }

            let resolution = FlyoverExportPolicy.resolution(for: snapshotCase)
            guard case let .policy(policy) = resolution else {
                Issue.record("Expected a resolved export policy.")
                return
            }
            #expect(policy.captureExtent == .viewport)
            #expect(policy.measurementReadiness == .immediate)
            #expect(policy.settle == .immediate)
        }

        @Test(
            arguments: [
                SizingExpectation(frame: .iPhone, extent: .viewport),
                SizingExpectation(frame: .component, extent: .intrinsic),
                SizingExpectation(frame: .iPhoneFullContent, extent: .fullContent),
                SizingExpectation(frame: .iPhoneFullContent2D, extent: .fullContent2D),
            ],
        )
        func reducesOneSizingClass(expectation: SizingExpectation) {
            let snapshotCase = SnapshotCase(
                name: "Sizing",
                configurations: [SnapshotConfiguration(device: expectation.frame)],
            ) {
                EmptyView()
            }

            let resolution = FlyoverExportPolicy.resolution(for: snapshotCase)
            guard case let .policy(policy) = resolution else {
                Issue.record("Expected a resolved export policy.")
                return
            }
            #expect(policy.captureExtent == expectation.extent)
        }

        @Test func reportsMixedSizingClasses() {
            let snapshotCase = SnapshotCase(
                name: "Mixed",
                configurations: [
                    SnapshotConfiguration(device: .iPhone),
                    SnapshotConfiguration(device: .iPhoneFullContent),
                ],
            ) {
                EmptyView()
            }

            let resolution = FlyoverExportPolicy.resolution(for: snapshotCase)
            guard case let .mixed(extents) = resolution else {
                Issue.record("Expected a mixed sizing policy.")
                return
            }
            #expect(Set(extents) == [.viewport, .fullContent])
        }

        struct SizingExpectation {
            let frame: SnapshotConfiguration.Frame
            let extent: FlyoverCaptureExtent
        }
    }
#endif
