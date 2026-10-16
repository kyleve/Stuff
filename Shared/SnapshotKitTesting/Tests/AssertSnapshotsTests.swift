import SnapshotKit
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AssertSnapshotsTests {
    @Test func assertionWaitsForCaptureBeforeResolvingTheHostWidth() async throws {
        try waitFor { hostKeyWindow() != nil }
        let originalWidth = try #require(hostKeyWindow()).bounds.width
        let probe = AssertionCaptureQueueProbe()
        let holder = Task { @MainActor in
            try await captureSnapshotPNG(
                of: Color.red,
                configuration: SnapshotConfiguration(device: .init(
                    name: "holder",
                    size: .fixed(CGSize(width: 80, height: 60)),
                )),
                named: "assertion-queue-holder",
                sizing: .fixed,
                safeAreaInsets: .zero,
                measurementReadiness: .sameAsCapture,
                onReadyToMeasure: nil,
                settle: .immediate,
                onReadyToSnapshot: {
                    probe.holderStarted = true
                    while !probe.canFinishHolder, !Task.isCancelled {
                        await Task.yield()
                    }
                },
            )
        }
        defer {
            probe.canFinishHolder = true
            holder.cancel()
        }
        try await waitForAsync { probe.holderStarted }

        let name = UUID().uuidString
        let source: StaticString = "/tmp/SnapshotKitFixtureProbes/Fixture.swift"
        let assertion = Task { @MainActor in
            probe.assertionStarted = true
            await withKnownIssue("Recording a temporary image intentionally reports an issue") {
                await assertSnapshots(
                    of: Color.blue.frame(height: 40),
                    named: "Queued",
                    configurations: [SnapshotConfiguration(device: .init(
                        name: "host-width",
                        size: .intrinsic(maxWidth: nil),
                    ))],
                    measurementReadiness: .immediate,
                    settle: .immediate,
                    record: .all,
                    file: source,
                    testName: name,
                )
            } matching: { issue in
                if case .unconditional = issue.kind {
                    return issue.comments.contains {
                        $0.rawValue.hasPrefix("Record mode is on. Automatically recorded snapshot:")
                    }
                }
                return false
            }
        }
        try await waitForAsync { probe.assertionStarted }
        probe.canFinishHolder = true
        _ = try await holder.value
        await assertion.value

        let reference = snapshotReferenceURL(
            testFilePath: "\(source)",
            testName: name,
            identifier: "Queued_host-width",
        )
        let image = try #require(UIImage(contentsOfFile: reference.path))
        let pixels = try #require(image.cgImage)
        let scale = try #require(hostKeyWindow()).traitCollection.displayScale
        #expect(CGFloat(pixels.width) == originalWidth * scale)
        #expect(image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5)).blue > 0.5)
        try FileManager.default.removeItem(at: reference)
    }

    @Test func mountedHostResizesWithoutReplacingViewState() async throws {
        let probe = SnapshotResizeProbeState()
        let host = UIHostingController(rootView: SnapshotResizeProbe(state: probe))
        let frames: [SnapshotConfiguration.Frame] = [
            .narrowWindow,
            .iPad,
            .viewport(
                name: "short-window",
                size: CGSize(width: 640, height: 320),
                layoutTraits: .init(
                    horizontalSizeClass: .regular,
                    verticalSizeClass: .compact,
                    interfaceIdiom: .pad,
                ),
            ),
            .narrowWindow,
        ]
        try await show(host) { controller in
            var firstIdentity: UUID?
            for frame in frames {
                guard case let .fixed(size) = frame.size else {
                    Issue.record("Resize fixtures must have explicit viewport bounds.")
                    return
                }
                let traits = try #require(frame.layoutTraits)
                SnapshotConfiguration(device: frame).applyTraits(to: controller)
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.layoutIfNeeded()
                do {
                    try await waitForAsync {
                        probe.size == size
                            && probe.horizontal == traits.horizontalSizeClass.swiftUISizeClass
                            && probe.vertical == traits.verticalSizeClass.swiftUISizeClass
                            && probe.identity != nil
                    }
                } catch {
                    Issue
                        .record(
                            "Resize \(frame.name): measured \(String(describing: probe.size)), horizontal \(String(describing: probe.horizontal)), vertical \(String(describing: probe.vertical)), identity \(String(describing: probe.identity))",
                        )
                    throw error
                }
                if let firstIdentity {
                    #expect(probe.identity == firstIdentity)
                } else {
                    firstIdentity = probe.identity
                }
            }
        }
    }

    @Test func providerConstructsFreshContentForEachConfiguration() async throws {
        IndependentSnapshotProvider.probes = []
        let name = UUID().uuidString
        let source: StaticString = "/tmp/SnapshotKitFixtureProbes/Fixture.swift"
        await withKnownIssue("Recording temporary images intentionally reports issues") {
            await assertSnapshots(
                of: IndependentSnapshotProvider.self,
                record: .all,
                file: source,
                testName: name,
            )
        } matching: { issue in
            if case .unconditional = issue.kind {
                return issue.comments.contains {
                    $0.rawValue.hasPrefix("Record mode is on. Automatically recorded snapshot:")
                }
            }
            return false
        }
        #expect(IndependentSnapshotProvider.probes.count == 2)
        #expect(IndependentSnapshotProvider.probes.allSatisfy { $0.mutations == 1 })
        for identifier in ["Independent", "Independent_second"] {
            let url = snapshotReferenceURL(
                testFilePath: "\(source)",
                testName: name,
                identifier: identifier,
            )
            let image = try #require(UIImage(contentsOfFile: url.path))
            let center = image.probePixel(atUnitPoint: CGPoint(x: 0.5, y: 0.5))
            #expect(center.green > 0.5)
            #expect(center.red < 0.5)
            try FileManager.default.removeItem(at: url)
        }
        IndependentSnapshotProvider.probes = []
    }

    @Test func removingExplicitLayoutTraitsRestoresInheritance() {
        let host = UIHostingController(rootView: Color.clear)
        SnapshotConfiguration(device: .iPad).applyTraits(to: host)
        #expect(host.traitOverrides.contains(UITraitUserInterfaceIdiom.self))
        SnapshotConfiguration().applyTraits(to: host)
        #expect(host.traitOverrides.contains(UITraitUserInterfaceIdiom.self) == false)
        #expect(host.traitOverrides.contains(UITraitHorizontalSizeClass.self) == false)
        #expect(host.traitOverrides.contains(UITraitVerticalSizeClass.self) == false)
    }

    @Test func configuredLayoutTraitsReachSwiftUIAndUIKit() throws {
        let probe = SnapshotLayoutProbeState()
        let host = makeHostingController(
            for: SnapshotLayoutProbe(state: probe),
            configuration: SnapshotConfiguration(device: .iPad),
            hostWidth: 402,
        )
        try show(host) { controller in
            try waitFor { probe.horizontal == .regular && probe.vertical == .regular }
            #expect(controller.traitCollection.userInterfaceIdiom == .pad)
        }
    }

    @Test func componentWithoutLayoutTraitsInheritsTheHost() throws {
        let probe = SnapshotLayoutProbeState()
        let host = makeHostingController(
            for: SnapshotLayoutProbe(state: probe),
            configuration: SnapshotConfiguration(),
            hostWidth: 320,
        )
        #expect(host.view.frame.width == 402)
        try show(host) { controller in
            controller.traitOverrides.horizontalSizeClass = .regular
            controller.traitOverrides.verticalSizeClass = .compact
            try waitFor { probe.horizontal == .regular && probe.vertical == .compact }
        }
    }

    @Test func previewAndCaptureUseTheSameLayoutTraits() throws {
        let probe = SnapshotLayoutProbeState()
        let host = UIHostingController(rootView: SnapshotLayoutProbe(state: probe)
            .snapshotTraits(SnapshotConfiguration(device: .narrowWindow)))
        try show(host) { _ in
            try waitFor { probe.horizontal == .compact && probe.vertical == .regular }
        }
    }

    @Test func intrinsicFallbackUsesMarkedHostWidth() {
        let frame = SnapshotConfiguration.Frame(name: "unbounded", size: .intrinsic(maxWidth: nil))
        let host = makeHostingController(
            for: Color.green,
            configuration: SnapshotConfiguration(device: frame),
            hostWidth: 731,
        )
        #expect(host.view.frame.width == 731)
    }

    @Test func cancellationDuringMeasurementReadinessEndsQuietly() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let assertion = Task { @MainActor in
            await assertSnapshots(
                of: Color.green.frame(width: 100, height: 100),
                named: "cancelled-measurement-readiness",
                configurations: [SnapshotConfiguration()],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    probe.didStart = true
                    while Task.isCancelled == false {
                        await Task.yield()
                    }
                },
                settle: .immediate,
            )
        }

        while probe.didStart == false {
            await Task.yield()
        }
        assertion.cancel()
        await assertion.value
    }

    @Test func cancelledProviderDoesNotBuildItsNextCase() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let hooks = ProviderCancellationHooks(
            waitForCancellation: {
                probe.didStart = true
                while Task.isCancelled == false {
                    await Task.yield()
                }
            },
            didBuildSecondCase: {
                probe.didBuildSecondCase = true
            },
        )

        await ProviderCancellationContext.$hooks.withValue(hooks) {
            let assertion = Task { @MainActor in
                await assertSnapshots(of: CancellationSnapshotProvider.self)
            }
            while probe.didStart == false {
                await Task.yield()
            }
            assertion.cancel()
            await assertion.value
        }

        #expect(probe.didBuildSecondCase == false)
    }
}

@MainActor
private final class AssertionCaptureQueueProbe {
    var holderStarted = false
    var canFinishHolder = false
    var assertionStarted = false
}

@MainActor
private final class MeasurementHookCancellationProbe {
    var didStart = false
    var didBuildSecondCase = false
}

private struct ProviderCancellationHooks {
    let waitForCancellation: @MainActor @Sendable () async -> Void
    let didBuildSecondCase: @MainActor @Sendable () -> Void
}

private enum ProviderCancellationContext {
    @TaskLocal static var hooks: ProviderCancellationHooks?
}

private struct CancellationSnapshotProvider: SnapshotProviding {
    @MainActor static var snapshots: [SnapshotCase] {
        let hooks = ProviderCancellationContext.hooks
        SnapshotCase(
            name: "cancelled-first-case",
            configurations: [
                SnapshotConfiguration(
                    device: SnapshotConfiguration.Frame(
                        name: "intrinsic",
                        size: .intrinsic(maxWidth: 100),
                    ),
                ),
            ],
            measurementReadiness: .immediate,
            onReadyToMeasure: hooks?.waitForCancellation,
            settle: .immediate,
        ) {
            Color.red.frame(height: 40)
        }
        SnapshotCase(
            name: "must-not-build",
            configurations: [SnapshotConfiguration()],
            settle: .immediate,
        ) {
            let _ = hooks?.didBuildSecondCase()
            Color.blue
        }
    }
}

@MainActor
private final class SnapshotLayoutProbeState {
    var horizontal: UserInterfaceSizeClass?
    var vertical: UserInterfaceSizeClass?
}

private struct SnapshotLayoutProbe: View {
    let state: SnapshotLayoutProbeState
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    var body: some View {
        Color.clear
            .onChange(of: horizontal, initial: true) { _, value in state.horizontal = value }
            .onChange(of: vertical, initial: true) { _, value in state.vertical = value }
    }
}

@MainActor
private final class SnapshotResizeProbeState {
    var size: CGSize?
    var horizontal: UserInterfaceSizeClass?
    var vertical: UserInterfaceSizeClass?
    var identity: UUID?
}

private struct SnapshotResizeProbe: View {
    let state: SnapshotResizeProbeState
    @State private var identity = UUID()
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { $0.size } action: { state.size = $0 }
            .onChange(of: horizontal, initial: true) { _, value in state.horizontal = value }
            .onChange(of: vertical, initial: true) { _, value in state.vertical = value }
            .onAppear { state.identity = identity }
            // Expand the geometry probe itself, not only its painted background.
            .ignoresSafeArea()
    }
}
