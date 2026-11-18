@_spi(Capture) import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

extension SnapshotPortrait {
    static func render(
        caseName: String,
        configuration: SnapshotConfiguration,
        backend: Backend,
    ) throws -> Frame {
        let snapshotCase = try #require(FlightStatusBanner.snapshots.first { $0.name == caseName })
        return try render(snapshotCase, configuration: configuration, backend: backend)
    }
}

@MainActor
struct BannerFrameProbeTests {
    private struct Result: Codable {
        let id: String
        let backend: String
        let width: Int
        let height: Int
        let mounts: Int
        let fullDraws: Int
        let renderSeconds: Double
        let equalPNG: Bool
        let passesImageAssertion: Bool
        let reference: String
    }

    @Test func portraits() async throws {
        guard let directory = ProcessInfo.processInfo.environment["REQUESTED_FRAME_OUTPUT"],
              !directory.isEmpty else { throw SnapshotPortrait.Failure.missingOutputDirectory }
        let output = URL(fileURLWithPath: directory).appendingPathComponent("banner")
        let suite = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("FlightStatusBannerSnapshotTests.swift")
        var results: [Result] = []
        let cases = FlightStatusBanner.snapshots
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await benchmark(cases: cases, directory: output)
        for backend in SnapshotPortrait.Backend.allCases {
            let folder = output.appendingPathComponent(backend.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for sample in cases {
                for configuration in sample.configurations
                    where configuration.snapshotType == .standard
                {
                    let id = ([sample.name] + configuration.identifierParts).joined(separator: "_")
                    let expected = snapshotReferenceURL(
                        testFilePath: suite.path,
                        testName: "flightStatusBanner()",
                        identifier: id,
                        configuration: configuration,
                        referenceGroup: sample.referenceGroup,
                    )
                    let start = CACurrentMediaTime()
                    let frame = try SnapshotPortrait.render(
                        sample,
                        configuration: configuration,
                        backend: backend,
                    )
                    let elapsed = CACurrentMediaTime() - start
                    try frame.png.write(
                        to: folder.appendingPathComponent(id + ".png"),
                        options: .atomic,
                    )
                    let reference = try Data(contentsOf: expected)
                    let passes = try Self.accepts(frame.png, reference: reference)
                    results.append(Result(
                        id: id,
                        backend: backend.rawValue,
                        width: frame.width,
                        height: frame.height,
                        mounts: frame.mounts,
                        fullDraws: frame.fullDraws,
                        renderSeconds: elapsed,
                        equalPNG: frame.png == reference,
                        passesImageAssertion: passes,
                        reference: expected.path,
                    ))
                    print(
                        "BANNER_FRAME \(backend.rawValue) \(id) \(frame.width)x\(frame.height) mounts=\(frame.mounts) fullDraws=\(frame.fullDraws) intentionalSleeps=0 seconds=\(elapsed) accepted=\(passes)",
                    )
                }
            }
            #expect(results.count(where: { $0.backend == backend.rawValue }) == 20)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(
            to: output.appendingPathComponent("results.json"),
            options: .atomic,
        )
        try verifyRejections(cases: cases, directory: output)
    }

    private enum TimedBackend: String {
        case production, native
    }

    private struct Request {
        let sample: SnapshotCase
        let configuration: SnapshotConfiguration
        let id: String
    }

    private struct TimedFrame: Encodable {
        let id: String
        let seconds: Double
        let width: Int
        let height: Int
    }

    private struct Matrix: Encodable {
        let backend: String
        let wallSeconds: Double
        let frames: [TimedFrame]
    }

    /// Time fixture construction through encoded PNG and dimensions. Reference access,
    /// disk exports, and equivalence checks run after both matrices have completed.
    private func benchmark(cases: [SnapshotCase], directory: URL) async throws {
        let requests = cases.flatMap { sample in
            sample.configurations.filter { $0.snapshotType == .standard }.map { configuration in
                Request(
                    sample: sample,
                    configuration: configuration,
                    id: ([sample.name] + configuration.identifierParts).joined(separator: "_"),
                )
            }
        }
        let warmup = try #require(requests.first)
        let pass = ProcessInfo.processInfo.environment["REQUESTED_FRAME_PASS"]
        let order: [TimedBackend] = pass == "repeat" ? [.native, .production] : [
            .production,
            .native,
        ]
        for backend in order {
            _ = try await benchmarkRender(warmup, backend: backend)
        }
        var runs: [Matrix] = []
        var images: [String: [Data]] = [:]
        for backend in order {
            var frames: [TimedFrame] = []
            var outputs: [Data] = []
            let start = CACurrentMediaTime()
            for request in requests {
                let began = CACurrentMediaTime()
                let (png, size) = try await benchmarkRender(request, backend: backend)
                frames.append(TimedFrame(
                    id: request.id,
                    seconds: CACurrentMediaTime() - began,
                    width: Int(size.width),
                    height: Int(size.height),
                ))
                outputs.append(png)
            }
            let elapsed = CACurrentMediaTime() - start
            runs.append(Matrix(backend: backend.rawValue, wallSeconds: elapsed, frames: frames))
            images[backend.rawValue] = outputs
            print("BANNER_MATRIX \(backend.rawValue) frames=\(frames.count) seconds=\(elapsed)")
        }
        let production = try #require(images[TimedBackend.production.rawValue])
        let candidate = try #require(images[TimedBackend.native.rawValue])
        #expect(requests.count == 20 && Set(requests.map(\.id)).count == 20)
        let controlRows = try #require(runs
            .first { $0.backend == TimedBackend.production.rawValue })
        let candidateRows = try #require(runs.first { $0.backend == TimedBackend.native.rawValue })
        for index in requests.indices {
            #expect(
                production[index] == candidate[index],
                "Separate native hosts must produce identical PNGs for \(requests[index].id)",
            )
            #expect(controlRows.frames[index].width == candidateRows.frames[index].width)
            #expect(controlRows.frames[index].height == candidateRows.frames[index].height)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(runs).write(
            to: directory.appendingPathComponent("benchmark.json"),
            options: .atomic,
        )
    }

    private func benchmarkRender(
        _ request: Request,
        backend: TimedBackend,
    ) async throws -> (Data, CGSize) {
        switch backend {
            case .native:
                let frame = try SnapshotPortrait.render(
                    request.sample,
                    configuration: request.configuration,
                    backend: .native,
                )
                return (frame.png, CGSize(width: frame.width, height: frame.height))
            case .production:
                guard case let .single(build) = request.sample.capture,
                      case let .intrinsic(.some(width)) = request.configuration.device.size
                else { throw SnapshotPortrait.Failure.unsupportedRequest(request.id) }
                let output = try await captureSnapshotPNG(
                    of: build(),
                    configuration: request.configuration,
                    named: request.id,
                    sizing: .intrinsic(width: width, minimumHeight: 0),
                    safeAreaInsets: request.configuration.device.safeAreaInsets.uiEdgeInsets,
                    measurementReadiness: request.sample.measurementReadiness,
                    onReadyToMeasure: request.sample.onReadyToMeasure,
                    settle: request.sample.settle,
                    prepareForCapture: request.sample.prepareForCapture,
                    onReadyToSnapshot: request.sample.onReadyToSnapshot,
                )
                return (output.data, output.pixelSize)
        }
    }

    private func verifyRejections(cases: [SnapshotCase], directory: URL) throws {
        let correct = try #require(cases.first { $0.name == "UncertainArrival" })
        let wrong = try #require(cases.first { $0.name == "Waiting" })
        let configuration = SnapshotConfiguration()
        let reference = try Data(contentsOf: directory
            .appendingPathComponent("native/UncertainArrival.png"))
        let correctAgain = try SnapshotPortrait.render(
            correct,
            configuration: configuration,
            backend: .native,
        )
        #expect(try Self.accepts(correctAgain.png, reference: reference))
        let wrongState = try SnapshotPortrait.render(
            wrong,
            configuration: configuration,
            backend: .native,
        )
        let changedLayout = try SnapshotPortrait.render(
            correct,
            configuration: configuration,
            backend: .native,
            extraPadding: 13,
        )
        #expect(wrongState.width == correctAgain.width && wrongState.height == correctAgain.height)
        #expect(try !Self.accepts(wrongState.png, reference: reference))
        #expect(try !Self.accepts(changedLayout.png, reference: reference))
        let folder = directory.appendingPathComponent("witnesses")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try wrongState.png.write(
            to: folder.appendingPathComponent("wrong-state.png"),
            options: .atomic,
        )
        try changedLayout.png.write(
            to: folder.appendingPathComponent("wrong-layout.png"),
            options: .atomic,
        )
    }

    /// Use the ordinary pixel/perceptual verdict, including dimension differences.
    static func accepts(_ png: Data, reference: Data) throws -> Bool {
        if png == reference { return true }
        let scale = try #require(hostKeyWindow()?.traitCollection.displayScale)
        let expected = try #require(UIImage(data: reference, scale: scale))
        let actual = try #require(UIImage(data: png, scale: scale))
        return Snapshotting<UIImage, UIImage>.image(
            precision: defaultSnapshotPrecision,
            perceptualPrecision: defaultSnapshotPerceptualPrecision,
        ).diffing.diffV2(expected, actual) == nil
    }
}
