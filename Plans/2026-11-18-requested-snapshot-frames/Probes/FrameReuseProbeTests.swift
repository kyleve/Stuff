import CryptoKit
import Foundation
@_spi(Testing) import SnapshotKitTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

private final class FrameReuseBundleMarker: NSObject {}

@MainActor
struct FrameReuseProbeTests {
    private enum Failure: Error, Equatable {
        case unsupportedRequest, invalidScope
        case mismatchedSession([String])
    }

    /// Only these two complete configurations and this fixture have a known input contract.
    private enum Variant: String, Codable {
        case light, dark

        init(state: String, configuration: SnapshotConfiguration) throws {
            guard state == "UncertainArrival" else { throw Failure.unsupportedRequest }
            if configuration == SnapshotConfiguration() { self = .light }
            else if configuration == SnapshotConfiguration(colorScheme: .dark) { self = .dark }
            else { throw Failure.unsupportedRequest }
        }

        var configuration: SnapshotConfiguration {
            SnapshotConfiguration(colorScheme: self == .light ? .light : .dark)
        }
    }

    private struct Entry: Codable {
        var png: Data
        let digest: Data
        let width: Int
        let height: Int
        let variant: Variant
        let scope: [String: String]
    }

    private struct Observation: Codable {
        let request: String
        let outcome: String
        let seconds: Double
        let renders: Int
    }

    /// This scope is valid only inside the fresh directory allocated by run-prototype.
    /// The build hashes and environment reject a changed host or test product on repeat.
    private func scope(directory: URL) throws -> [String: String] {
        let process = ProcessInfo.processInfo
        let window = try #require(hostKeyWindow())
        let testProduct = try #require(Bundle(for: FrameReuseBundleMarker.self).executableURL)
        let hostProduct = try #require(Bundle.main.executableURL)
        func digest(_ file: URL) throws -> String {
            let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
            return Data(SHA256.hash(data: bytes)).base64EncodedString()
        }
        let hostLibrary = hostProduct.appendingPathExtension("debug.dylib")
        return try [
            "renderer": "native-uncertain-arrival-v1",
            "session": directory.standardizedFileURL.path,
            "simulator": #require(process.environment["SIMULATOR_UDID"]),
            "runtime": process.operatingSystemVersionString,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "viewport": String(describing: window.bounds.size),
            "scale": String(describing: window.traitCollection.displayScale),
            "idiom": String(describing: window.traitCollection.userInterfaceIdiom.rawValue),
            "horizontalSizeClass": String(describing: window.traitCollection.horizontalSizeClass
                .rawValue),
            "verticalSizeClass": String(describing: window.traitCollection.verticalSizeClass
                .rawValue),
            "testExecutable": digest(testProduct),
            "hostExecutable": digest(hostProduct),
            "hostDebugLibrary": digest(hostLibrary),
        ]
    }

    @Test func reusesOnlyAnIdenticalBoundedRequest() throws {
        let env = ProcessInfo.processInfo.environment
        func variable(_ key: String) throws -> String {
            try #require(env["REQUESTED_FRAME_" + key] ?? env["TEST_RUNNER_REQUESTED_FRAME_" + key])
        }
        let directory = try URL(fileURLWithPath: variable("CACHE"), isDirectory: true)
        let output = try URL(fileURLWithPath: variable("OUTPUT"), isDirectory: true)
        let pass = try variable("PASS")
        guard pass == "first" || pass == "repeat" else { throw Failure.invalidScope }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("session.json")
        let start = CACurrentMediaTime()
        let actualScope = try scope(directory: directory)
        if pass == "first" {
            guard try files.contentsOfDirectory(atPath: directory.path).isEmpty
            else { throw Failure.invalidScope }
            try JSONEncoder().encode(actualScope).write(to: manifest, options: .atomic)
        } else {
            let firstScope = try JSONDecoder().decode(
                [String: String].self,
                from: Data(contentsOf: manifest),
            )
            let keys = Set(actualScope.keys).union(firstScope.keys)
            let mismatches = keys.filter { actualScope[$0] != firstScope[$0] }.sorted()
            guard mismatches.isEmpty else { throw Failure.mismatchedSession(mismatches) }
        }
        let scopeSeconds = CACurrentMediaTime() - start
        let encoder = Foundation.PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = Foundation.PropertyListDecoder()
        var renders = 0
        var observations: [Observation] = []
        func file(_ variant: Variant) -> URL {
            directory.appendingPathComponent(variant.rawValue + ".plist")
        }

        func request(
            _ label: String,
            _ variant: Variant,
            expecting expected: String,
        ) throws -> Entry {
            let start = CACurrentMediaTime()
            var outcome = "missing"
            let before = renders
            defer {
                observations.append(Observation(
                    request: label,
                    outcome: outcome,
                    seconds: CACurrentMediaTime() - start,
                    renders: renders - before,
                ))
            }
            let path = file(variant)
            if files.fileExists(atPath: path.path) {
                let raw = try Data(contentsOf: path)
                if let stored = try? decoder.decode(Entry.self, from: raw),
                   stored.variant == variant, stored.scope == actualScope,
                   stored.digest == Data(SHA256.hash(data: stored.png)),
                   let image = UIImage(data: stored.png)?.cgImage,
                   image.width == stored.width, image.height == stored.height
                {
                    outcome = "hit"
                    #expect(outcome == expected)
                    return stored
                }
                outcome = "corrupt"
            }
            renders += 1
            let frame = try BannerPortrait.render(
                caseName: "UncertainArrival",
                configuration: variant.configuration,
                backend: .native,
            )
            let stored = Entry(
                png: frame.png,
                digest: Data(SHA256.hash(data: frame.png)),
                width: frame.width,
                height: frame.height,
                variant: variant,
                scope: actualScope,
            )
            try encoder.encode(stored).write(to: path, options: .atomic)
            #expect(outcome == expected)
            return stored
        }

        let suite = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("FlightStatusBannerSnapshotTests.swift")
        func reference(_ name: String, configuration: SnapshotConfiguration) throws -> Data {
            let url = snapshotReferenceURL(
                testFilePath: suite.path,
                testName: "flightStatusBanner()",
                identifier: name,
                configuration: configuration,
            )
            return try Data(contentsOf: url)
        }
        let light = try Variant(state: "UncertainArrival", configuration: SnapshotConfiguration())
        let dark = try Variant(
            state: "UncertainArrival",
            configuration: SnapshotConfiguration(colorScheme: .dark),
        )
        let expected = try reference("UncertainArrival", configuration: light.configuration)
        let initial = try request(
            "first lookup",
            light,
            expecting: pass == "first" ? "missing" : "hit",
        )
        #expect(try BannerFrameProbeTests.accepts(initial.png, reference: expected))
        let pixels = try #require(UIImage(data: expected)?.cgImage)
        #expect(initial.width == pixels.width && initial.height == pixels.height)

        let warm = try request("repeat lookup", light, expecting: "hit")
        #expect(try BannerFrameProbeTests.accepts(warm.png, reference: expected))
        let wrong = try reference("Waiting", configuration: light.configuration)
        let wrongPixels = try #require(UIImage(data: wrong)?.cgImage)
        #expect(wrongPixels.width == warm.width && wrongPixels.height == warm.height)
        let changedExpectation = try request("changed expectation", light, expecting: "hit")
        #expect(try !BannerFrameProbeTests.accepts(changedExpectation.png, reference: wrong))

        let appearance = try request("dark", dark, expecting: pass == "first" ? "missing" : "hit")
        #expect(try BannerFrameProbeTests.accepts(
            appearance.png,
            reference: reference(
                "UncertainArrival_dark",
                configuration: dark
                    .configuration,
            ),
        ))
        #expect(appearance.digest != initial.digest)
        var corrupted = initial
        corrupted.png = appearance.png
        try encoder.encode(corrupted).write(to: file(light), options: .atomic)
        let repaired = try request("recover substituted valid PNG", light, expecting: "corrupt")
        #expect(repaired.png == initial.png)
        try files.removeItem(at: file(light))
        let recovered = try request("recover missing entry", light, expecting: "missing")
        #expect(recovered.png == initial.png)
        #expect(throws: Failure.unsupportedRequest) { try Variant(
            state: "external",
            configuration: light.configuration,
        ) }
        #expect(throws: Failure.unsupportedRequest) {
            try Variant(
                state: "UncertainArrival",
                configuration: SnapshotConfiguration(contrast: .increased),
            )
        }

        let independentStart = CACurrentMediaTime()
        let fresh = try BannerPortrait.render(
            caseName: "UncertainArrival",
            configuration: light.configuration,
            backend: .native,
        )
        observations.append(Observation(
            request: "independent cold verification",
            outcome: "rendered",
            seconds: CACurrentMediaTime() - independentStart,
            renders: fresh.fullDraws,
        ))
        #expect(fresh.png == warm.png && fresh.width == warm.width && fresh.height == warm.height)
        #expect(renders == (pass == "first" ? 4 : 2))
        let json = JSONEncoder()
        json.outputFormatting = [.prettyPrinted, .sortedKeys]
        try json.encode(observations).write(
            to: output.appendingPathComponent("frame-reuse.json"),
            options: .atomic,
        )
        print(
            "FRAME_REUSE pass=\(pass) cacheRenders=\(renders) independentRenders=\(fresh.fullDraws) scopeSeconds=\(scopeSeconds)",
        )
    }
}
