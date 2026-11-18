import CryptoKit
@_spi(Capture) import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// A request always rebuilds the production view from its existing snapshot fixture.
@MainActor
enum SnapshotPortrait {
    enum Backend: String, CaseIterable {
        case direct
        case native
    }

    struct Frame {
        let png: Data
        let width: Int
        let height: Int
        let backend: Backend
        let mounts: Int
        let fullDraws: Int
    }

    enum Failure: Error {
        case missingOutputDirectory
        case unsupportedRequest(String)
        case invalidSize(CGSize)
        case unavailableRenderer
        case incompleteDraw
    }

    private struct Input<Content: View> {
        let content: Content
        let width: CGFloat
        let scale: CGFloat
    }

    private static func prepare(
        _ snapshotCase: SnapshotCase,
        configuration: SnapshotConfiguration,
        extraPadding: CGFloat?,
        allowSettledDiagnostic: Bool,
    ) throws -> Input<some View> {
        guard configuration.snapshotType == .standard,
              case let .intrinsic(.some(width)) = configuration.device.size,
              case let .single(build) = snapshotCase.capture,
              allowSettledDiagnostic ||
              (snapshotCase.settle == .immediate && snapshotCase.measurementReadiness != .settled),
              snapshotCase.onReadyToMeasure == nil, snapshotCase.prepareForCapture == nil,
              snapshotCase.onReadyToSnapshot == nil
        else { throw Failure.unsupportedRequest(snapshotCase.name) }

        let scale = try #require(hostKeyWindow()?.traitCollection.displayScale)
        let regular = build()
        let view = extraPadding.map { AnyView(regular.padding($0)) } ?? regular
        let styled = view
            .environment(\.colorScheme, configuration.colorScheme)
            .dynamicTypeSize(configuration.dynamicType)
            .environment(\.layoutDirection, configuration.layoutDirection)
            .environment(\.legibilityWeight, configuration.legibilityWeight)
            .environment(\.displayScale, scale)
            .snapshotLayoutTraits(configuration)
            .transaction { $0.disablesAnimations = true; $0.animation = nil }

        return Input(content: styled, width: width, scale: scale)
    }

    static func render(
        _ snapshotCase: SnapshotCase,
        configuration: SnapshotConfiguration,
        backend: Backend,
        extraPadding: CGFloat? = nil,
        allowSettledDiagnostic: Bool = false,
    ) throws -> Frame {
        let input = try prepare(
            snapshotCase,
            configuration: configuration,
            extraPadding: extraPadding,
            allowSettledDiagnostic: allowSettledDiagnostic,
        )
        var mounts = 0
        var draws = 0
        let image: UIImage
        switch backend {
            case .direct:
                let renderer = ImageRenderer(content: input.content)
                renderer.proposedSize = ProposedViewSize(width: input.width, height: nil)
                renderer.scale = input.scale
                var rendered: UIImage?
                configuration.uiTraitCollection.performAsCurrent {
                    draws += 1
                    rendered = renderer.uiImage
                }
                guard let rendered else { throw Failure.unavailableRenderer }
                image = rendered
            case .native:
                let controller = try mount(input, configuration: configuration)
                mounts += 1
                defer { unmount(controller) }
                image = try draw(controller.view, scale: input.scale, draws: &draws)
        }
        return try frame(image, backend: backend, mounts: mounts, draws: draws)
    }

    static func renderAfterSettle(
        _ sample: SnapshotCase,
        configuration: SnapshotConfiguration,
        named id: String,
    ) async throws -> Frame {
        let timeout = try SnapshotSettleTimeoutPolicy.fromEnvironment()
        let input = try prepare(
            sample,
            configuration: configuration,
            extraPadding: nil,
            allowSettledDiagnostic: true,
        )
        let controller = try mount(input, configuration: configuration)
        defer { unmount(controller) }
        let maximum = timeout.maximumDuration(for: sample.settle)
        let outcome: SettleOutcome
        switch sample.settle {
            case .settled:
                outcome = await settleContent(
                    controller.view,
                    named: id,
                    maxDuration: maximum,
                    reason: .content,
                )
            case let .settledAtLeast(minDuration):
                outcome = await settleContent(
                    controller.view,
                    named: id,
                    minDuration: minDuration,
                    maxDuration: maximum,
                    reason: .content,
                )
            case .immediate:
                throw Failure.unsupportedRequest(id)
        }
        try Task.checkCancellation()
        switch outcome {
            case .settled: break
            case .cancelled: throw CancellationError()
            case .skipped: throw Failure.unsupportedRequest(id)
            case let .timedOut(budget):
                throw SnapshotRenderingError.settleTimedOut(
                    name: id,
                    phase: "content",
                    viewType: String(reflecting: type(of: controller)),
                    budget: budget,
                )
            case let .starved(passes, cap):
                throw SnapshotRenderingError.settleStarved(
                    name: id,
                    phase: "content",
                    viewType: String(reflecting: type(of: controller)),
                    passes: passes,
                    cap: cap,
                )
        }
        var draws = 0
        let image = try draw(controller.view, scale: input.scale, draws: &draws)
        return try frame(image, backend: .native, mounts: 1, draws: draws)
    }

    private static func mount(
        _ input: Input<some View>,
        configuration: SnapshotConfiguration,
    ) throws -> UIViewController {
        let width = input.width
        let parent = try #require(hostKeyWindow()?.rootViewController)
        let controller = UIHostingController(rootView: input.content)
        controller.safeAreaRegions = []
        controller.traitOverrides[SnapshotCaptureTrait.self] = true
        configuration.applyTraits(to: controller)
        let subject = controller.view!
        subject.backgroundColor = .clear
        subject.frame = CGRect(x: 0, y: 0, width: width, height: parent.view.bounds.height)
        parent.addChild(controller)
        parent.view.addSubview(subject)
        controller.didMove(toParent: parent)
        do {
            let proposal = CGSize(width: width, height: .greatestFiniteMagnitude)
            subject.setNeedsLayout()
            subject.layoutIfNeeded()
            let size = CGSize(width: width, height: subject.sizeThatFits(proposal).height)
            guard size.height.isFinite, size.height > 0, size.height < 2000 else {
                throw Failure.invalidSize(size)
            }
            subject.frame.size = size
            subject.setNeedsLayout()
            subject.layoutIfNeeded()
            guard abs(subject.sizeThatFits(proposal).height - size.height) < 0.5 else {
                throw Failure.invalidSize(size)
            }
            return controller
        } catch {
            unmount(controller)
            throw error
        }
    }

    private static func unmount(_ controller: UIViewController) {
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }

    private static func draw(
        _ subject: UIView,
        scale: CGFloat,
        draws: inout Int,
    ) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = scale
        var complete = false
        let image = UIGraphicsImageRenderer(bounds: subject.bounds, format: format).image { _ in
            draws += 1
            complete = subject.drawHierarchy(in: subject.bounds, afterScreenUpdates: true)
        }
        guard complete else { throw Failure.incompleteDraw }
        return image
    }

    private static func frame(
        _ image: UIImage,
        backend: Backend,
        mounts: Int,
        draws: Int,
    ) throws -> Frame {
        let pixels = try #require(image.cgImage)
        return try Frame(
            png: #require(image.pngData()),
            width: pixels.width,
            height: pixels.height,
            backend: backend,
            mounts: mounts,
            fullDraws: draws,
        )
    }
}

/// Runs only when the experiment launcher installs this file and a bundle's fixture list.
@MainActor
enum MountMatrix {
    struct Suite {
        let file: String
        let test: String
        let cases: [SnapshotCase]
    }

    private enum Arm: String, Codable {
        case production, immediateControl, native, settledNative
    }

    private enum Verdict: String, Codable {
        case identicalPNG, equalPixels, withinTolerance, differentPixels, differentDimensions
    }

    private struct Measurement: Encodable {
        let backend: Arm
        let seconds: Double
        var width: Int?
        var height: Int?
        var digest: String?
        var againstReference: Verdict?
        var error: String?
    }

    private struct Row: Encodable {
        let suite: String
        let test: String
        let identifier: String
        let referenceGroup: String?
        let reference: String
        let measurementReadiness: String
        let settle: String
        let cohort: String
        var excluded: String?
        var measurements: [Measurement] = []
        var candidateVsProduction: Verdict?
        var settledNativeVsProduction: Verdict?
        var candidateVsImmediateControl: Verdict?
        var artifacts: String?
    }

    private struct Report: Encodable {
        let bundle: String
        let pass: String
        var rows: [Row] = []
    }

    static func run(bundle: String, suites: [Suite], sourcePath: String) async throws {
        let env = ProcessInfo.processInfo.environment
        let root = try #require(env["REQUESTED_FRAME_OUTPUT"])
        let pass = try #require(env["REQUESTED_FRAME_PASS"])
        try #require(["first", "repeat"].contains(pass))
        let output = URL(fileURLWithPath: root).appendingPathComponent(bundle)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sources = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        var report = Report(bundle: bundle, pass: pass)
        var seen = Set<URL>()
        var warmed: Set<Arm> = []

        for suite in suites {
            for sample in suite.cases {
                for configuration in sample.configurations {
                    try Task.checkCancellation()
                    let identifier = [sample.name, configuration.identifier]
                        .filter { !$0.isEmpty }
                        .joined(separator: "_")
                    let reference = snapshotReferenceURL(
                        testFilePath: sources.appendingPathComponent(suite.file).path,
                        testName: suite.test,
                        identifier: identifier,
                        configuration: configuration,
                        referenceGroup: sample.referenceGroup,
                    )
                    let immediate = sample.settle == .immediate && sample
                        .measurementReadiness != .settled
                    var row = Row(
                        suite: suite.file,
                        test: suite.test,
                        identifier: identifier,
                        referenceGroup: sample.referenceGroup?.rawValue,
                        reference: reference.path,
                        measurementReadiness: String(describing: sample.measurementReadiness),
                        settle: String(describing: sample.settle),
                        cohort: immediate ? "immediate" : "settledDiagnostic",
                        excluded: exclusion(for: sample, configuration: configuration),
                    )
                    if row.excluded == nil {
                        try #require(
                            seen.insert(reference).inserted,
                            "Duplicate measured reference: \(reference.path)",
                        )
                        let target = try Data(contentsOf: reference)
                        var arms: [Arm] = immediate ? [.production, .native] : [
                            .production,
                            .immediateControl,
                            .native,
                        ]
                        if sample.measurementReadiness == .immediate && sample
                            .settle != .immediate
                        {
                            arms.append(.settledNative)
                        }
                        let order = pass == "first" ? arms : Array(arms.reversed())
                        // Give every backend its first unmeasured invocation before timing this
                        // row.
                        // An unsupported render is still measured and reported by the real attempt.
                        for arm in order where warmed.insert(arm).inserted {
                            _ = try? await render(
                                arm,
                                sample: sample,
                                configuration: configuration,
                                id: identifier,
                            )
                        }
                        var captures: [Arm: Data] = [:]
                        for arm in order {
                            let start = CACurrentMediaTime()
                            do {
                                let (png, size) = try await render(
                                    arm,
                                    sample: sample,
                                    configuration: configuration,
                                    id: identifier,
                                )
                                let elapsed = CACurrentMediaTime() - start
                                captures[arm] = png
                                row.measurements.append(Measurement(
                                    backend: arm,
                                    seconds: elapsed,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    digest: Data(SHA256.hash(data: png)).base64EncodedString(),
                                ))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                row.measurements.append(Measurement(
                                    backend: arm,
                                    seconds: CACurrentMediaTime() - start,
                                    error: String(describing: error),
                                ))
                            }
                        }
                        for index in row.measurements.indices {
                            let arm = row.measurements[index].backend
                            if let png = captures[arm] {
                                row.measurements[index].againstReference = try compare(
                                    png,
                                    to: target,
                                )
                            }
                        }
                        if let settled = captures[.settledNative],
                           let current = captures[.production]
                        {
                            row.settledNativeVsProduction = try compare(settled, to: current)
                        }
                        if let native = captures[.native], let current = captures[.production] {
                            row.candidateVsProduction = try compare(native, to: current)
                        }
                        if let native = captures[.native],
                           let control = captures[.immediateControl]
                        {
                            row.candidateVsImmediateControl = try compare(native, to: control)
                        }
                        if row.measurements
                            .contains(where: { $0.againstReference != .identicalPNG })
                        {
                            let relative = "differences/\(report.rows.count)-\(reference.deletingPathExtension().lastPathComponent)"
                            let directory = output.appendingPathComponent(relative)
                            try FileManager.default.createDirectory(
                                at: directory,
                                withIntermediateDirectories: true,
                            )
                            try target.write(to: directory.appendingPathComponent("reference.png"))
                            for (arm, data) in captures {
                                try data
                                    .write(to: directory
                                        .appendingPathComponent("\(arm.rawValue).png"))
                            }
                            row.artifacts = relative
                        }
                    }
                    report.rows.append(row)
                }
            }
            // Flush completed suites so a later fixture timeout retains earlier results.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(report).write(
                to: output.appendingPathComponent("matrix.json"),
                options: .atomic,
            )
            print("MOUNT_MATRIX \(bundle) \(suite.file) pass=\(pass) rows=\(report.rows.count)")
        }
        try #require(!seen.isEmpty, "No eligible captures in \(bundle)")
    }

    private static func exclusion(
        for sample: SnapshotCase,
        configuration: SnapshotConfiguration,
    ) -> String? {
        guard case .single = sample.capture else { return "cutsheet" }
        guard configuration.snapshotType == .standard else { return "annotation" }
        guard case .intrinsic(.some) = configuration.device.size else { return "sizing" }
        guard configuration.device.safeAreaInsets == .zero else { return "nonzero safe area" }
        guard sample.onReadyToMeasure == nil, sample.prepareForCapture == nil,
              sample.onReadyToSnapshot == nil else { return "readiness hook" }
        return nil
    }

    private static func render(
        _ arm: Arm,
        sample: SnapshotCase,
        configuration: SnapshotConfiguration,
        id: String,
    ) async throws -> (Data, CGSize) {
        if arm == .settledNative {
            let frame = try await SnapshotPortrait.renderAfterSettle(
                sample,
                configuration: configuration,
                named: id,
            )
            return (frame.png, CGSize(width: frame.width, height: frame.height))
        }
        if arm == .native {
            let frame = try SnapshotPortrait.render(
                sample,
                configuration: configuration,
                backend: .native,
                allowSettledDiagnostic: true,
            )
            return (frame.png, CGSize(width: frame.width, height: frame.height))
        }
        guard case let .single(build) = sample.capture,
              case let .intrinsic(.some(width)) = configuration.device.size
        else {
            throw SnapshotPortrait.Failure.unsupportedRequest(id)
        }
        let control = arm == .immediateControl
        let frame = try await captureSnapshotPNG(
            of: build(),
            configuration: configuration,
            named: id,
            sizing: .intrinsic(width: width, minimumHeight: 0),
            safeAreaInsets: configuration.device.safeAreaInsets.uiEdgeInsets,
            measurementReadiness: control ? .immediate : sample.measurementReadiness,
            onReadyToMeasure: nil,
            settle: control ? .immediate : sample.settle,
            prepareForCapture: nil,
            onReadyToSnapshot: nil,
        )
        return (frame.data, frame.pixelSize)
    }

    /// Use the repository's ordinary image comparison and a strict decoded-pixel comparison
    /// separately.
    private static func compare(_ actual: Data, to expected: Data) throws -> Verdict {
        if actual == expected { return .identicalPNG }
        let scale = try #require(hostKeyWindow()?.traitCollection.displayScale)
        let a = try #require(UIImage(data: actual, scale: scale))
        let e = try #require(UIImage(data: expected, scale: scale))
        guard a.size == e.size else { return .differentDimensions }
        let exact = Snapshotting<UIImage, UIImage>.image(precision: 1, perceptualPrecision: 1)
        if exact.diffing.diffV2(e, a) == nil { return .equalPixels }
        let ordinary = Snapshotting<UIImage, UIImage>.image(
            precision: defaultSnapshotPrecision,
            perceptualPrecision: defaultSnapshotPerceptualPrecision,
        )
        return ordinary.diffing.diffV2(e, a) == nil ? .withinTolerance : .differentPixels
    }
}
