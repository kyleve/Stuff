import Observation
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct CapturePreparationTests {
    @Test func preparationRunsWhileHostedBeforeSettlingAndItsEffectIsCaptured() async throws {
        try waitFor { hostKeyWindow() != nil }
        let model = PreparationProbeModel()
        let host = UIHostingController(rootView: PreparationProbeView(model: model))
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let timing = SnapshotCaptureTiming(identifier: "prepared", isEnabled: true)
        var preparationRan = false

        let capture = try await renderSnapshotCapture(
            of: host,
            named: "prepared",
            sizing: .fixed,
            safeAreaInsets: .zero,
            isAccessibility: false,
            measurementReadiness: .sameAsCapture,
            onReadyToMeasure: nil,
            settle: .settled,
            prepareForCapture: {
                #expect(host.view.window != nil)
                #expect(host.parent != nil)
                let phases = try decodedPhases(timing)
                #expect(phases["settle"] == nil, "Preparation must not pay an initial settle.")
                while !model.hostedTaskRan {
                    try Task.checkCancellation()
                    await Task.yield()
                }
                model.prepared = true
                preparationRan = true
            },
            onReadyToSnapshot: nil,
            settleTimeoutPolicy: .parse(nil),
            timing: timing,
        )

        #expect(preparationRan)
        let pixel = capture.image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
        #expect(pixel.green > 0.5 && pixel.red < 0.5 && pixel.blue < 0.5)
        let phases = try decodedPhases(timing)
        #expect(phases["preparationHook"] != nil)
        #expect(try #require(phases["settle"]) >= 0.25)
        #expect(phases["hook"] == nil)
    }

    @Test func preparationFailureRestoresTheHostAndPreservesTheError() async throws {
        try waitFor { hostKeyWindow() != nil }
        let root = try #require(hostKeyWindow()?.rootViewController)
        let initialChildren = root.children
        let host = UIHostingController(rootView: Color.green)
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        var finalHookRan = false

        await #expect(throws: URLError(.fileDoesNotExist)) {
            try await renderSnapshotImage(
                of: host,
                named: "failed-preparation",
                prepareForCapture: { throw URLError(.fileDoesNotExist) },
                onReadyToSnapshot: { finalHookRan = true },
            )
        }

        #expect(!finalHookRan)
        #expect(host.parent == nil)
        #expect(host.view.window == nil)
        #expect(root.children == initialChildren)
        let recovered = try await renderSnapshotImage(
            of: host,
            named: "after-failed-preparation",
            settle: .immediate,
        )
        #expect(recovered.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5)).green > 0.5)
    }

    @Test func cancellationDuringPreparationRestoresTheHost() async throws {
        try waitFor { hostKeyWindow() != nil }
        let root = try #require(hostKeyWindow()?.rootViewController)
        let initialChildren = root.children
        let host = UIHostingController(rootView: Color.green)
        host.view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let started = AsyncStream<Void>.makeStream()
        let suspended = AsyncStream<Void>.makeStream()
        defer {
            started.continuation.finish()
            suspended.continuation.finish()
        }
        var preparationFinished = false
        var finalHookRan = false
        let task = Task {
            try await renderSnapshotImage(
                of: host,
                named: "cancelled-preparation",
                prepareForCapture: {
                    started.continuation.yield(())
                    defer { preparationFinished = true }
                    for await _ in suspended.stream {}
                },
                onReadyToSnapshot: { finalHookRan = true },
            )
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(preparationFinished)
        #expect(!finalHookRan)
        #expect(host.parent == nil)
        #expect(host.view.window == nil)
        #expect(root.children == initialChildren)
    }

    @Test func preparationTimeoutCancelsTheHook() async {
        var finished = false
        await #expect(throws: SnapshotRenderingError.capturePreparationTimedOut(
            name: "preparation-timeout",
            budget: 0.02,
        )) {
            try await runSnapshotPreparationHook(
                named: "preparation-timeout",
                maximumDuration: 0.02,
            ) {
                defer { finished = true }
                try await Task.sleep(for: .seconds(60))
            }
        }
        #expect(finished)
    }

    private func decodedPhases(_ timing: SnapshotCaptureTiming) throws -> [String: Double] {
        struct Line: Decodable {
            let phases: [String: Double]
        }
        let json = try #require(timing.line())
        return try JSONDecoder().decode(Line.self, from: Data(json.utf8)).phases
    }
}

@Observable
private final class PreparationProbeModel {
    var hostedTaskRan = false
    var prepared = false
}

private struct PreparationProbeView: View {
    let model: PreparationProbeModel

    var body: some View {
        (model.prepared ? Color.green : .red)
            .frame(width: 100, height: 100)
            .task { model.hostedTaskRan = true }
    }
}
