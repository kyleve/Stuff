import SnapshotKit
import SnapshotTesting
@_spi(Testing) @testable import SnapshotKitTesting
import SwiftUI
import Synchronization
import TestHostSupport
import Testing
import UIKit

@MainActor
struct AssertSnapshotsTests {
    @Test func exhaustedConfigurationRecordsOnceAndContinuesToTheNext() async {
        var attempts = 0
        let failures = Mutex(0)
        await withKnownIssue("Two configurations exhaust their retries", isIntermittent: false) {
            await assertSnapshots(
                of: Color.green.frame(width: 40, height: 40),
                named: "exhausted",
                configurations: [.init(), .init(colorScheme: .dark)],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    attempts += 1
                    throw snapshotRetryTimeout(attempt: attempts)
                },
                settle: .immediate,
                record: .never,
            )
        } matching: { issue in
            guard let error = issue.error as? SnapshotRenderingError,
                  error == snapshotRetryTimeout(attempt: 3)
                  || error == snapshotRetryTimeout(attempt: 6)
            else { return false }
            failures.withLock { $0 += 1 }
            return true
        }
        #expect(attempts == 6)
        #expect(failures.withLock { $0 } == 2)
    }

    @Test(arguments: [1, 3])
    func recoveredCaptureReachesComparisonOnlyOnce(successfulAttempt: Int) async {
        var attempts = 0
        let comparisons = Mutex(0)
        await withKnownIssue("The probe deliberately has no reference", isIntermittent: false) {
            await assertSnapshots(
                of: Color.green.frame(width: 40, height: 40),
                named: "recovered-without-reference",
                configurations: [.init()],
                measurementReadiness: .immediate,
                onReadyToMeasure: {
                    attempts += 1
                    if attempts < successfulAttempt {
                        throw snapshotRetryTimeout(attempt: attempts)
                    }
                },
                settle: .immediate,
                record: .never,
            )
        } matching: { issue in
            guard issue.error == nil,
                  issue.comments.contains(where: { $0.rawValue.contains("No reference was found") })
            else { return false }
            comparisons.withLock { $0 += 1 }
            return true
        }
        #expect(attempts == successfulAttempt)
        #expect(comparisons.withLock { $0 } == 1)
    }

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
            configuration: SnapshotConfiguration(device: .init(
                name: "host-width",
                size: .intrinsic(maxWidth: nil),
            )),
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
                configuration: SnapshotConfiguration(),
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

    @Test func cancelledProviderDoesNotBuildItsNextCaseOrConfiguration() async throws {
        try waitFor { hostKeyWindow() != nil }
        let probe = MeasurementHookCancellationProbe()
        let hooks = ProviderCancellationHooks(
            waitForCancellation: {
                probe.didStart = true
                while Task.isCancelled == false {
                    await Task.yield()
                }
            },
            didBuildContent: { probe.contentBuildCount += 1 },
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
        #expect(probe.contentBuildCount == 1)
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
    var contentBuildCount = 0
}

private struct ProviderCancellationHooks {
    let waitForCancellation: @MainActor @Sendable () async -> Void
    let didBuildContent: @MainActor @Sendable () -> Void
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
                SnapshotConfiguration(colorScheme: .dark),
            ],
            measurementReadiness: .immediate,
            onReadyToMeasure: hooks?.waitForCancellation,
            settle: .immediate,
        ) {
            hooks?.didBuildContent()
            return Color.red.frame(height: 40)
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

@MainActor
struct SnapshotAssertionPipelineTests {
    @Test(.snapshots(record: .all))
    func providerPreservesInheritedPolicyAndExplicitOverrides() async throws {
        try await checkProviderRecording(record: nil, shouldRecord: true)
        try await withSnapshotTesting(record: .never) {
            try await checkProviderRecording(record: nil, shouldRecord: false)
        }
        try await withSnapshotTesting(record: .all) {
            try await checkProviderRecording(record: .never, shouldRecord: false)
        }
    }

    @Test func providerPreservesDefaultMissingPolicy() async throws {
        try await checkProviderRecording(record: nil, shouldRecord: true)
    }

    @Test func drainsPendingComparisonBeforeHostingCutsheet() async {
        let issues = Mutex(0)
        let cases = [
            overlapCase(0) {},
            SnapshotCase.cutsheet(
                name: "Middle",
                configurations: [.init()],
                measurementReadiness: .immediate,
                settle: .immediate,
                prepareForCapture: { #expect(issues.withLock { $0 } == 1) },
            ) {
                SnapshotPanel(id: .init(rawValue: "one"), label: "One") {
                    Color.blue.frame(width: 40, height: 40)
                }
            },
            overlapCase(2) { #expect(issues.withLock { $0 } == 2) },
        ]
        await withKnownIssue("Temporary mixed references are missing", isIntermittent: false) {
            await runOverlapCases(cases)
        } matching: { issue in
            guard issue.comments.contains(where: { $0.rawValue.contains("No reference was found") })
            else { return false }
            issues.withLock { $0 += 1 }
            return true
        }
        #expect(issues.withLock { $0 } == 3)
    }

    private func checkProviderRecording(
        record: SnapshotTestingConfiguration.Record?,
        shouldRecord: Bool,
    ) async throws {
        let name = UUID().uuidString
        let source: StaticString = "/tmp/SnapshotKitOverlapProbes/Policy.swift"
        let issues = Mutex(0)
        let references = ["Before", "Middle", "After"].map { identifier in
            snapshotReferenceURL(
                testFilePath: source.description,
                testName: name,
                identifier: identifier,
                configuration: .init(),
            )
        }
        defer {
            for reference in references
                where FileManager.default.fileExists(atPath: reference.path)
            {
                do { try FileManager.default.removeItem(at: reference) }
                catch { Issue.record(error) }
            }
        }
        await withKnownIssue(
            "Missing/recorded temporary references report once",
            isIntermittent: false,
        ) {
            await assertSnapshots(
                of: OverlapRecordingProvider.self,
                record: record,
                file: source,
                testName: name,
            )
        } matching: { issue in
            guard issue.comments.contains(where: {
                $0.rawValue.contains("No reference was found")
                    || $0.rawValue.contains("Record mode is on")
            }) else { return false }
            issues.withLock { $0 += 1 }
            return true
        }
        #expect(issues.withLock { $0 } == 3)
        for reference in references {
            #expect(FileManager.default.fileExists(atPath: reference.path) == shouldRecord)
        }
    }

    @Test func overlapsOnlyOneWorkerAndDrainsEveryAssertion() async {
        let state = Mutex(OverlapProbeState())
        let releases = AsyncStream<Void>.makeStream()
        defer { releases.continuation.finish() }
        let cases = (0 ..< 3).map { index in
            overlapCase(index) {
                state.withLock { $0.captures.append(index) }
                if index > 0 {
                    try await waitForAsync { state.withLock { $0.workersStarted >= index } }
                    releases.continuation.yield(())
                }
            }
        }
        await withKnownIssue(
            "Temporary captures intentionally have no references",
            isIntermittent: false,
        ) {
            await runOverlapCases(cases) { _, _, _ in
                let ordinal = state.withLock { value in
                    let ordinal = value.workersStarted
                    value.workersStarted += 1
                    value.activeWorkers += 1
                    value.maximumWorkers = max(value.maximumWorkers, value.activeWorkers)
                    return ordinal
                }
                if ordinal < 2 {
                    for await _ in releases.stream {
                        break
                    }
                }
                state.withLock { value in
                    value.observedFollowingCapture.append(value.captures.count >= ordinal + 2)
                    value.activeWorkers -= 1
                }
                return overlapSerialResult()
            }
        } matching: { issue in
            guard issue.comments
                .contains(where: { $0.rawValue.contains("No reference was found") })
            else { return false }
            state.withLock { $0.issues.append(issue.comments.map(\.rawValue).joined()) }
            return true
        }
        let value = state.withLock { $0 }
        #expect(value.captures == [0, 1, 2])
        #expect(value.workersStarted == 3)
        #expect(value.maximumWorkers == 1)
        #expect(value.activeWorkers == 0)
        #expect(Array(value.observedFollowingCapture.prefix(2)) == [true, true])
        #expect(value.issues.count == 3)
    }

    @Test func cancellationDrainsWorkerAndHostedCaptureBeforeReturning() async throws {
        try waitFor { hostKeyWindow() != nil }
        let root = try #require(hostKeyWindow()?.rootViewController)
        let children = root.children
        let animations = UIView.areAnimationsEnabled
        let workerStarted = AsyncStream<Void>.makeStream()
        let secondCaptureStarted = AsyncStream<Void>.makeStream()
        let workerWait = AsyncStream<Void>.makeStream()
        let captureWait = AsyncStream<Void>.makeStream()
        defer {
            workerStarted.continuation.finish()
            secondCaptureStarted.continuation.finish()
            workerWait.continuation.finish()
            captureWait.continuation.finish()
        }
        let workerExited = Mutex(false)
        let references = Mutex<[URL]>([])
        var captures: [Int] = []
        let cases = (0 ..< 3).map { index in
            overlapCase(index) {
                captures.append(index)
                if index == 1 {
                    secondCaptureStarted.continuation.yield(())
                    for await _ in captureWait.stream {}
                    try Task.checkCancellation()
                }
            }
        }
        let task = Task { @MainActor in
            await runOverlapCases(cases, record: .failed) { _, reference, _ in
                references.withLock { $0.append(reference) }
                workerStarted.continuation.yield(())
                for await _ in workerWait.stream {}
                workerExited.withLock { $0 = true }
                return SnapshotPreparedComparison(
                    outcome: .cancelled,
                    duration: 0,
                )
            }
        }
        for await _ in workerStarted.stream {
            break
        }
        for await _ in secondCaptureStarted.stream {
            break
        }
        task.cancel()
        await task.value
        #expect(workerExited.withLock { $0 })
        #expect(references.withLock { $0 }.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
        #expect(captures == [0, 1])
        #expect(root.children == children)
        #expect(UIView.areAnimationsEnabled == animations)
    }

    @Test func reportsEarlierComparisonBeforeLaterCaptureErrorAndContinues() async {
        let issues = Mutex<[String]>([])
        let cases = (0 ..< 3).map { index in
            overlapCase(index) {
                if index == 1 { throw URLError(.cannotLoadFromNetwork) }
            }
        }
        await withKnownIssue(
            "Missing references and one deliberate readiness failure",
            isIntermittent: false,
        ) {
            await runOverlapCases(cases) { _, _, _ in overlapSerialResult() }
        } matching: { issue in
            if issue.error as? URLError == URLError(.cannotLoadFromNetwork) {
                issues.withLock { $0.append("capture-error") }
                return true
            }
            guard issue.comments
                .contains(where: { $0.rawValue.contains("No reference was found") })
            else { return false }
            issues.withLock { $0.append(issue.comments.map(\.rawValue).joined()) }
            return true
        }
        let results = issues.withLock { $0 }
        #expect(results.count == 3)
        if results.count == 3 {
            #expect(results[0].contains("No reference was found"))
            #expect(results[1] == "capture-error")
            #expect(results[2].contains("No reference was found"))
        }
    }

    private func overlapCase(
        _ index: Int,
        preparation: @escaping @MainActor @Sendable () async throws -> Void,
    ) -> SnapshotCase {
        SnapshotCase(
            name: "Overlap-\(index)",
            configurations: [.init(device: .init(
                name: "probe",
                size: .fixed(CGSize(width: 40, height: 40)),
            ))],
            settle: .immediate,
            prepareForCapture: preparation,
        ) {
            Color.green
        }
    }

    private func runOverlapCases(
        _ cases: [SnapshotCase],
        record: SnapshotTestingConfiguration.Record? = .never,
        prepare: @escaping @Sendable (Data, URL, Bool) async
            -> SnapshotPreparedComparison = { png, reference, diagnostics in
                await prepareSnapshotReference(
                    capturedPNG: png,
                    referenceURL: reference,
                    diagnostics: diagnostics,
                )
            },
    ) async {
        await assertOverlappingSnapshots(
            cases,
            record: record,
            fileID: #fileID,
            file: "/tmp/SnapshotKitOverlapProbes/Probe.swift",
            testName: UUID().uuidString,
            line: #line,
            column: #column,
            prepare: prepare,
        )
    }
}

private struct OverlapProbeState {
    var captures: [Int] = []
    var workersStarted = 0
    var activeWorkers = 0
    var maximumWorkers = 0
    var observedFollowingCapture: [Bool] = []
    var issues: [String] = []
}

private func overlapSerialResult() -> SnapshotPreparedComparison {
    SnapshotPreparedComparison(outcome: .serial, duration: 0)
}

private struct OverlapRecordingProvider: SnapshotProviding {
    @MainActor static var snapshots: [SnapshotCase] {
        SnapshotCase(
            name: "Before",
            configurations: [.init()],
            measurementReadiness: .immediate,
            settle: .immediate,
        ) {
            Color.red.frame(width: 40, height: 40)
        }
        SnapshotCase.cutsheet(
            name: "Middle",
            configurations: [.init()],
            measurementReadiness: .immediate,
            settle: .immediate,
        ) {
            SnapshotPanel(id: .init(rawValue: "one"), label: "One") {
                Color.blue.frame(width: 40, height: 40)
            }
        }
        SnapshotCase(
            name: "After",
            configurations: [.init()],
            measurementReadiness: .immediate,
            settle: .immediate,
        ) {
            Color.green.frame(width: 40, height: 40)
        }
    }
}
