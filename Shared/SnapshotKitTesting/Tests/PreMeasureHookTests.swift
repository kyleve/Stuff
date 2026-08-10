import Observation
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Regression guards for `onReadyToMeasure`: the hook runs only while the
/// intrinsic probe is hosted, and its completion precedes size resolution.
@MainActor
struct PreMeasureHookTests {
    @Test func hostedHookCanReleaseHeightChangingAsyncContentBeforeMeasurement() async throws {
        try waitFor { hostKeyWindow() != nil }
        let model = PreMeasureProbeModel()
        let host = UIHostingController(rootView: PreMeasureProbeView(model: model))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 1)

        let image = try await renderSnapshotImage(
            of: host,
            named: "pre-measure-hook-probe",
            sizing: .intrinsic(width: 100, minimumHeight: 0),
            safeAreaInsets: .zero,
            measurementReadiness: .immediate,
            onReadyToMeasure: {
                while model.hostedTaskRan == false {
                    await Task.yield()
                }
            },
            settle: .immediate,
        )

        #expect(model.hostedTaskRan)
        #expect(image.size.height == 180)
    }

    @Test func fixedCaptureRejectsAMeasurementHook() async throws {
        try waitFor { hostKeyWindow() != nil }
        let host = UIHostingController(rootView: Color.green)
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        await #expect(
            throws: SnapshotRenderingError.measurementHookRequiresIntrinsicSizing(
                name: "fixed-pre-measure-hook",
            ),
        ) {
            try await renderSnapshotImage(
                of: host,
                named: "fixed-pre-measure-hook",
                onReadyToMeasure: {},
            )
        }
    }
}

@Observable
private final class PreMeasureProbeModel {
    var hostedTaskRan = false
}

private struct PreMeasureProbeView: View {
    let model: PreMeasureProbeModel

    var body: some View {
        Color.green
            .frame(width: 100, height: model.hostedTaskRan ? 180 : 40)
            .task { model.hostedTaskRan = true }
    }
}
