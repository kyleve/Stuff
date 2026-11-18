import AccessibilitySnapshotParser
import Foundation
import RegionKit
import SnapshotKit
import SwiftUI
import TestHostSupport
import Testing
import UIKit
import WhereCore
@testable import WhereUI

/// Temporarily compiled into WhereUITests by the experiment runner.
@MainActor
struct LocationsFrameProbeTests {
    private enum Stage: String, CaseIterable {
        case loading, loaded, selected
    }

    private struct Frame: Encodable {
        let stage: String
        let mode: String
        let mount: Int
        let width: Int
        let height: Int
        let complete: Bool
        let witnessBefore: String
        let witnessAfter: String
        let actionSeconds: Double
        let readinessSeconds: Double
        let drawSeconds: Double
        let oracleDelaySeconds: Double
    }

    private struct Timings: Encodable {
        let pass: String
        let executionOrder: [String]
        let candidate: [String: Double]
        let oracle: [String: Double]
        let negative: [String: Double]
    }

    @MainActor
    private final class Measurements {
        let mode: String
        var mountOffset: Int
        var mounts = 0
        var draws = 0
        var wallSeconds = 0.0
        var gateEntrySeconds = 0.0
        var oracleDelaySeconds = 0.0
        var actionSeconds = 0.0
        var witnessSeconds = 0.0

        init(_ mode: String, mountOffset: Int = 0) {
            self.mode = mode
            self.mountOffset = mountOffset
        }

        var summary: [String: Double] {
            [
                "mounts": Double(mounts),
                "firstMount": Double(mountOffset + 1),
                "lastMount": Double(mountOffset + mounts),
                "draws": Double(draws),
                "wallIncludingExportSeconds": wallSeconds,
                "wallExcludingOracleDelaySeconds": wallSeconds - oracleDelaySeconds,
                "gateEntrySeconds": gateEntrySeconds,
                "oracleDelaySeconds": oracleDelaySeconds,
                "actionSeconds": actionSeconds,
                "witnessPollingSeconds": witnessSeconds,
            ]
        }
    }

    /// A genuinely blocked initial store read. Once release is requested, repeat
    /// the release until refresh finishes: TestStore installs its continuation
    /// after reading its backing store, so an early release alone could be lost.
    @MainActor
    private final class Scenario {
        let measurements: Measurements
        var lastActionSeconds = 0.0
        let store: TestStore
        let report: YearReportModel
        weak var mountedController: UIViewController?
        var lastSelectionConditions = ""
        let navigation = LocationsView.Navigation()
        let artwork = RegionOutlinePathCache()
        private var finished = false
        private var refresh: Task<Void, Never>?

        init(measurements: Measurements) async throws {
            self.measurements = measurements
            store = try TestStore()
            report = PlanningTestSupport.report(store: store)
            try await report.services.journal.addManualDay(
                date: PlanningTestSupport.now,
                regions: [.california],
                audit: nil,
            )
            await store.enableFirstSamplesGate()
            refresh = Task {
                await self.report.refresh()
                self.finished = true
            }
        }

        func releaseRead() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !finished {
                try Task.checkCancellation()
                await store.releaseFirstSamplesCall()
                guard ContinuousClock.now < deadline else {
                    throw TestHostError(
                        "Locations report did not finish after releasing the store read",
                    )
                }
                if !finished { try await Task.sleep(for: .milliseconds(2)) }
            }
        }

        func waitForFirstRead() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while await store.sampleReadCount == 0 {
                guard ContinuousClock.now < deadline else {
                    throw TestHostError("Locations never requested the gated initial report")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        }

        func close() async throws {
            refresh?.cancel()
            // Teardown also runs when the calling test has been cancelled.
            try await Task { @MainActor in try await self.releaseRead() }.value
        }
    }

    @Test func capturesNamedLocationsFrames() async throws {
        let env = ProcessInfo.processInfo.environment
        let path =
            try #require(env["REQUESTED_FRAME_OUTPUT"] ?? env["TEST_RUNNER_REQUESTED_FRAME_OUTPUT"])
        let output = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("locations")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let pass = env["REQUESTED_FRAME_PASS"] ?? env["TEST_RUNNER_REQUESTED_FRAME_PASS"] ?? "first"
        try #require(["first", "repeat"].contains(pass))
        let candidate = Measurements("candidate")
        let oracle = Measurements("oracle")
        let order = pass == "repeat" ? [oracle, candidate] : [candidate, oracle]
        var mounted = 0
        for measurements in order {
            measurements.mountOffset = mounted
            if measurements === candidate {
                try await captureCandidate(candidate, output: output)
            } else {
                try await captureOracles(oracle, output: output)
            }
            mounted += measurements.mounts
        }
        let negative = Measurements("negative", mountOffset: mounted)
        try await withScenario(negative) { scenario, view in
            _ = try await waitForWitness(.loading, scenario: scenario, view: view)
            let rejectsUndelivered = try await remainsUnavailable(
                .loaded,
                scenario: scenario,
                view: view,
            )
            try await advance(to: .loaded, scenario: scenario, view: view)
            _ = try await waitForWitness(.loaded, scenario: scenario, view: view)
            let rejectsMissingAction = try await remainsUnavailable(
                .selected,
                scenario: scenario,
                view: view,
            )
            try write(
                [
                    "withheldDeliveryRejected": rejectsUndelivered,
                    "withheldSelectionRejected": rejectsMissingAction,
                ],
                to: output.appendingPathComponent("negative.json"),
            )
            #expect(rejectsUndelivered && rejectsMissingAction)
        }
        try write(
            Timings(
                pass: pass,
                executionOrder: (order + [negative]).map(\.mode),
                candidate: candidate.summary,
                oracle: oracle.summary,
                negative: negative.summary,
            ),
            to: output.appendingPathComponent("timings.json"),
        )
        print(
            "REQUESTED_FRAME_LOCATIONS candidateHosts=\(candidate.mounts) candidateDraws=\(candidate.draws) oracleHosts=\(oracle.mounts) oracleDraws=\(oracle.draws) negativeHosts=\(negative.mounts) candidateWallIncludingExport=\(candidate.wallSeconds) oracleWallIncludingExport=\(oracle.wallSeconds) oracleDisplayDelay=\(oracle.oracleDelaySeconds)",
        )
    }

    /// One mounted screen supplies all candidate frames.
    private func captureCandidate(_ candidate: Measurements, output: URL) async throws {
        try await withScenario(candidate) { scenario, view in
            for stage in Stage.allCases {
                try await advance(to: stage, scenario: scenario, view: view)
                try await save(
                    stage,
                    scenario: scenario,
                    view: view,
                    output: output,
                )
            }
        }
    }

    /// Each oracle owns a fresh store, model, navigation, artwork cache and controller.
    private func captureOracles(_ oracle: Measurements, output: URL) async throws {
        for target in Stage.allCases {
            try await withScenario(oracle) { scenario, view in
                for stage in Stage.allCases {
                    try await advance(to: stage, scenario: scenario, view: view)
                    if stage == target { break }
                    _ = try await waitForWitness(stage, scenario: scenario, view: view)
                }
                try await save(
                    target,
                    scenario: scenario,
                    view: view,
                    output: output,
                )
            }
        }
    }

    private func withScenario(
        _ measurements: Measurements,
        _ run: (Scenario, UIView) async throws -> Void,
    ) async throws {
        let started = ProcessInfo.processInfo.systemUptime
        defer { measurements.wallSeconds += ProcessInfo.processInfo.systemUptime - started }
        let scenario = try await Scenario(measurements: measurements)
        do {
            let host = UIHostingController(rootView: LocationsView(
                report: scenario.report,
                navigation: scenario.navigation,
            )
            .environment(\.regionOutlinePathCache, scenario.artwork)
            .whereBroadwayRoot())
            host.traitOverrides[SnapshotCaptureTrait.self] = true
            host.traitOverrides.userInterfaceStyle = .light
            host.traitOverrides.preferredContentSizeCategory = .large
            host.traitOverrides.horizontalSizeClass = .compact
            host.traitOverrides.verticalSizeClass = .regular
            try await show(host) { mounted in
                measurements.mounts += 1
                scenario.mountedController = mounted
                mounted.view.window?.layer.speed = 1
                mounted.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
                mounted.view.setNeedsLayout()
                mounted.view.layoutIfNeeded()
                let gateStart = ProcessInfo.processInfo.systemUptime
                try await scenario.waitForFirstRead()
                measurements.gateEntrySeconds += ProcessInfo.processInfo.systemUptime - gateStart
                try await run(scenario, mounted.view)
            }
        } catch {
            try await scenario.close()
            throw error
        }
        try await scenario.close()
    }

    private func visibleObjects(in view: UIView) -> [NSObject] {
        let viewport = view.convert(view.bounds, to: nil)
        return HostedAccessibility.objects(in: view).filter {
            let frame = $0.accessibilityFrame
            guard !frame.isEmpty, frame.intersects(viewport) else { return false }
            if let candidate = $0 as? UIView {
                guard candidate.window != nil else { return false }
                var node: UIView? = candidate
                while let ancestor = node {
                    if ancestor.isHidden || ancestor.alpha <= 0.01 { return false }
                    node = ancestor.superview
                }
            }
            return true
        }
    }

    private var expectedCardLabel: String {
        WhereFormat.regionDaysAccessibility(region: Region.california.localizedName, days: 1)
    }

    private func californiaCard(in objects: [NSObject]) -> NSObject? {
        objects
            .first {
                $0.accessibilityLabel == expectedCardLabel && $0.accessibilityTraits
                    .contains(.button)
            }
    }

    private func witness(_ stage: Stage, scenario: Scenario, view: UIView) -> String? {
        let objects = visibleObjects(in: view)
        let caption = String(localized: .primaryLoading)
        let loading = objects.first { $0.accessibilityLabel == caption }
        switch stage {
            case .loading:
                guard scenario.report.loadState == .loading else { return nil }
                return loading?.accessibilityLabel
            case .loaded:
                guard scenario.report.loadState == .loaded, loading == nil,
                      scenario.navigation.selectedRegion == nil else { return nil }
                return californiaCard(in: objects)?.accessibilityLabel
            case .selected:
                guard scenario.navigation.selectedRegion == .california else { return nil }
                let title = WhereFormat.calendarRegionTitle(
                    region: .california,
                    year: scenario.report.selectedYear,
                )
                let changeMode = String(localized: .calendarShowYear)
                let monthName = PlanningTestSupport.now.formatted(
                    Date
                        .FormatStyle(
                            date: .omitted,
                            time: .omitted,
                            calendar: scenario.report.calendar,
                            timeZone: scenario.report.calendar.timeZone,
                        ).month(.wide)
                        .year(),
                )
                let viewport = view.convert(view.bounds.inset(by: view.safeAreaInsets), to: nil)
                // AX and UIKit convert rect edges through different coordinate
                // spaces. Allow one physical pixel for the bottom-aligned card.
                let pixel = 1 / view.traitCollection.displayScale
                let visibleViewport = viewport.insetBy(dx: -pixel, dy: -pixel)
                let month = objects.first {
                    $0.accessibilityLabel?.contains(monthName) == true
                        && $0.accessibilityLabel?.contains(expectedCardLabel) == true
                }
                let hasTitle = objects.contains { $0.accessibilityLabel == title }
                let hasToolbar = objects
                    .contains {
                        $0.accessibilityLabel == changeMode && !$0.accessibilityTraits
                            .contains(.notEnabled)
                    }
                let hasMonth = month
                    .map { visibleViewport.contains($0.accessibilityFrame) } ?? false
                let navigators = scenario.mountedController.map(attachedNavigation(in:)) ?? []
                let navigationReady = !navigators.isEmpty && navigators
                    .allSatisfy { $0.transitionCoordinator == nil }
                scenario.lastSelectionConditions = "title=\(hasTitle), toolbar=\(hasToolbar), fullMonth=\(hasMonth) [\(monthName)], navCount=\(navigators.count), navCompleted=\(navigationReady)"
                // The title appears during the native push. The production
                // calendar later scrolls its last month to the bottom. Its AX
                // element covers the whole card, including the region/day legend.
                guard hasTitle, hasToolbar, hasMonth, navigationReady,
                      let label = month?.accessibilityLabel else { return nil }
                return [title, changeMode, label].joined(separator: " | ")
        }
    }

    private func attachedNavigation(in controller: UIViewController) -> [UINavigationController] {
        var result = controller.children.flatMap(attachedNavigation(in:))
        if let nav = controller as? UINavigationController, nav.isViewLoaded,
           nav.view.window != nil
        {
            result.append(nav)
        }
        return result
    }

    private func waitForWitness(
        _ stage: Stage,
        scenario: Scenario,
        view: UIView,
    ) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            scenario.measurements.witnessSeconds += ProcessInfo.processInfo.systemUptime - start
        }
        var observed: String?
        do {
            try await waitForAsync(timeout: .seconds(5)) {
                observed = witness(stage, scenario: scenario, view: view)
                return observed != nil
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let labels = visibleObjects(in: view).compactMap(\.accessibilityLabel).prefix(20)
            let controls = visibleObjects(in: view).compactMap { node -> String? in
                guard let label = node.accessibilityLabel,
                      label.contains("September") || label.contains("Year") || label
                      .contains("California") else { return nil }
                return "\(label): \(node.accessibilityFrame)"
            }
            throw TestHostError(
                "Missing \(stage.rawValue) on the visible screen; \(scenario.lastSelectionConditions). Visible elements: \(Array(labels)); calendar: \(controls); viewport: \(view.convert(view.bounds.inset(by: view.safeAreaInsets), to: nil))",
            )
        }
        return try #require(observed)
    }

    private func remainsUnavailable(
        _ stage: Stage,
        scenario: Scenario,
        view: UIView,
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(150))
        while ContinuousClock.now < deadline {
            if witness(stage, scenario: scenario, view: view) != nil { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return witness(stage, scenario: scenario, view: view) == nil
    }

    private func advance(to stage: Stage, scenario: Scenario, view: UIView) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            scenario.lastActionSeconds = ProcessInfo.processInfo.systemUptime - start
            scenario.measurements.actionSeconds += scenario.lastActionSeconds
        }
        switch stage {
            case .loading: break
            case .loaded: try await scenario.releaseRead()
            case .selected:
                let button = try #require(californiaCard(in: visibleObjects(in: view)))
                if let control = button as? UIControl {
                    control.sendActions(for: .touchUpInside)
                } else {
                    try #require(
                        button.accessibilityActivate(),
                        "California card must accept the production action",
                    )
                }
        }
    }

    private func save(
        _ stage: Stage,
        scenario: Scenario,
        view: UIView,
        output: URL,
    ) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let mode = scenario.measurements.mode
        _ = try await waitForWitness(stage, scenario: scenario, view: view)
        let ready = ProcessInfo.processInfo.systemUptime - start
        let oracleStart = ProcessInfo.processInfo.systemUptime
        if mode == "oracle" { try await Task.sleep(for: .milliseconds(600)) }
        let oracleDelay = mode == "oracle" ? ProcessInfo.processInfo.systemUptime - oracleStart : 0
        scenario.measurements.oracleDelaySeconds += oracleDelay
        view.layoutIfNeeded()
        let before = try #require(witness(stage, scenario: scenario, view: view))
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        format.scale = 3
        var complete = false
        let drawStart = ProcessInfo.processInfo.systemUptime
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            scenario.measurements.draws += 1
            complete = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let draw = ProcessInfo.processInfo.systemUptime - drawStart
        try #require(complete, "UIKit reported missing pixels in \(stage.rawValue)")
        let after = try #require(witness(stage, scenario: scenario, view: view))
        let cg = try #require(image.cgImage)
        let directory = output.appendingPathComponent(mode)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = directory.appendingPathComponent(stage.rawValue)
        let png = try #require(image.pngData())
        try png.write(to: stem.appendingPathExtension("png"), options: .atomic)
        try write(
            Frame(
                stage: stage.rawValue,
                mode: mode,
                mount: scenario.measurements.mountOffset + scenario.measurements.mounts,
                width: cg.width,
                height: cg.height,
                complete: complete,
                witnessBefore: before,
                witnessAfter: after,
                actionSeconds: scenario.lastActionSeconds,
                readinessSeconds: ready,
                drawSeconds: draw,
                oracleDelaySeconds: oracleDelay,
            ),
            to: stem.appendingPathExtension("json"),
        )
        print(
            "REQUESTED_FRAME_LOCATIONS \(mode) \(stage.rawValue) witness=\(after) ready=\(ready) draw=\(draw)",
        )
    }

    private func write(_ record: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
    }
}
