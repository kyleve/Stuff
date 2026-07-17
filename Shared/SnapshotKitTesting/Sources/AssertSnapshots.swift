import SnapshotKit
import SnapshotTesting
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Asserts every case × configuration a ``SnapshotProviding`` declares, recording
/// each against a reference image named by the case name + the configuration's
/// identifier. Records only missing images when the suite carries
/// `.snapshots(record: .missing)`; existing-image mismatches always fail.
///
/// `async` because the render pipeline must suspend for SwiftUI `.task`-driven
/// content to load before capture — see
/// ``renderSnapshotImage(of:sizing:safeAreaInsets:isAccessibility:)``.
@MainActor
public func assertSnapshots(
    of provider: (some SnapshotProviding).Type,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) async {
    guard simulatorMatchesSnapshotExpectations() else { return }
    let snapshots = provider.snapshots
    let duplicates = duplicateSnapshotIdentifiers(in: snapshots)
    guard duplicates.isEmpty else {
        Issue.record(
            """
            Duplicate snapshot identifiers in \(provider): \
            \(duplicates.joined(separator: ", ")). Two variants would share one \
            reference image — whichever records first, the other silently compares \
            against it — so nothing was asserted. Rename the colliding cases or \
            differentiate their configurations.
            """,
        )
        return
    }
    for snapshotCase in snapshots {
        await assertSnapshots(
            of: snapshotCase.content,
            named: snapshotCase.name,
            configurations: snapshotCase.configurations,
            settle: snapshotCase.settle,
            onReadyToSnapshot: snapshotCase.onReadyToSnapshot,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column,
        )
    }
}

/// Asserts a single view across a set of configurations, for one-off views that
/// don't warrant a ``SnapshotProviding`` conformance.
@MainActor
public func assertSnapshots(
    of view: some View,
    named name: String,
    configurations: [SnapshotConfiguration],
    settle: SnapshotSettle = .settled,
    onReadyToSnapshot: (@MainActor () async -> Void)? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) async {
    guard simulatorMatchesSnapshotExpectations() else { return }
    do {
        try waitFor { hostKeyWindow() != nil }
    } catch {
        Issue.record("Snapshot host window never appeared: \(error)")
        return
    }

    // The explicit parameter wins; the environment override (forwarded as
    // TEST_RUNNER_SNAPSHOT_RECORD on the command line) beats the suite trait,
    // so a re-record run needs no source edits. `nil` falls through to the
    // suite's `.snapshots(record:)` trait. The diff tool is env-only
    // (TEST_RUNNER_SNAPSHOT_DIFF_TOOL); `nil` keeps the default plain output.
    let resolvedRecord = record ?? environmentRecordMode()
    let resolvedDiffTool = environmentDiffTool()

    for configuration in configurations {
        let hostingController = makeHostingController(for: view, configuration: configuration)
        let sizing: SnapshotSizing = switch configuration.device.size {
            case .fixed:
                .fixed
            case let .intrinsic(maxWidth):
                .intrinsic(width: maxWidth ?? UIScreen.main.bounds.width)
            case let .fullContent(width):
                // Same measured-height pipeline as `.intrinsic`: a `ScrollView`
                // measured under the unbounded proposal reports its content
                // height (guarded by `LargeViewCaptureTests`), so the capture
                // renders the whole scrollable content.
                .intrinsic(width: width)
        }
        let identifier = fullSnapshotIdentifier(caseName: name, configuration: configuration)
        let image = await renderSnapshotImage(
            of: hostingController,
            sizing: sizing,
            isAccessibility: configuration.snapshotType == .accessibility,
            settle: settle,
            onReadyToSnapshot: onReadyToSnapshot,
        )
        withSnapshotTesting(record: resolvedRecord, diffTool: resolvedDiffTool) {
            assertSnapshot(
                of: image,
                as: .image(
                    precision: defaultSnapshotPrecision,
                    perceptualPrecision: defaultSnapshotPerceptualPrecision,
                ),
                named: identifier,
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column,
            )
        }
    }
}

/// The diff tool forwarded through the test environment: `SNAPSHOT_DIFF_TOOL`
/// (reaching the test process as `TEST_RUNNER_SNAPSHOT_DIFF_TOOL=…`). `ksdiff`
/// maps to the Kaleidoscope tool; absent or unknown values keep the default
/// plain file-URL output — the diff tool only shapes failure messages, so an
/// unknown value degrading to the default is harmless, unlike a record-mode
/// typo.
private func environmentDiffTool() -> SnapshotTestingConfiguration.DiffTool? {
    guard let value = ProcessInfo.processInfo.environment["SNAPSHOT_DIFF_TOOL"] else { return nil }
    switch value {
        case "ksdiff": return .ksdiff
        default: return nil
    }
}

/// The record mode forwarded through the test environment: `SNAPSHOT_RECORD`
/// set to `all`, `failed`, `missing`, or `never` (reaching the test process as
/// `TEST_RUNNER_SNAPSHOT_RECORD=…` on a tuist/xcodebuild command line — see the
/// module README for the re-record flow). `nil` when the variable is absent. An
/// unrecognized value records an issue rather than silently falling back to the
/// suite default — a typo'd re-record run must not quietly assert instead.
@MainActor
private func environmentRecordMode() -> SnapshotTestingConfiguration.Record? {
    guard let value = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] else { return nil }
    guard let record = SnapshotTestingConfiguration.Record(rawValue: value) else {
        Issue.record(
            """
            Unrecognized SNAPSHOT_RECORD value "\(value)" — use "all", "failed", \
            "missing", or "never".
            """,
        )
        return nil
    }
    return record
}

/// Fails fast when the live simulator doesn't match the environment the
/// reference images were recorded on.
///
/// The snapshot scheme's test action (see `testScheme` in `Project.swift`) pins
/// the recording environment via `SNAPSHOT_EXPECTED_SIMULATOR_RUNTIME_VERSION`
/// and `SNAPSHOT_EXPECTED_SCREEN_SCALE`. When those are present but don't match
/// the live simulator, every image comparison would fail with confusing
/// pixel diffs — so this records ONE clear issue naming the mismatch and the
/// runner asserts nothing. When the expectation variables are absent (direct
/// `renderSnapshotImage` callers, non-scheme invocations), the guard is inert.
@MainActor
private func simulatorMatchesSnapshotExpectations() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    var mismatches: [String] = []

    if let expectedRuntime = environment["SNAPSHOT_EXPECTED_SIMULATOR_RUNTIME_VERSION"] {
        let actualRuntime = environment["SIMULATOR_RUNTIME_VERSION"] ?? "unknown"
        if actualRuntime != expectedRuntime {
            mismatches.append(
                "references were recorded on simulator runtime \(expectedRuntime); this run is on \(actualRuntime)",
            )
        }
    }

    if let expectedScale = environment["SNAPSHOT_EXPECTED_SCREEN_SCALE"] {
        let actualScale = Double(UIScreen.main.scale)
        if Double(expectedScale) != actualScale {
            mismatches.append(
                """
                references were recorded at \(expectedScale)x screen scale; \
                this run is at \(actualScale.formatted())x
                """,
            )
        }
    }

    guard mismatches.isEmpty else {
        Issue.record(
            """
            Snapshot simulator mismatch: \(mismatches.joined(separator: "; ")). \
            Every comparison would fail confusingly, so nothing was asserted. Run on the \
            pinned simulator, or update the scheme's SNAPSHOT_EXPECTED_* test environment \
            variables in Project.swift alongside re-recorded references.
            """,
        )
        return false
    }
    return true
}

/// Builds a hosting controller for `view` with the configuration's appearance
/// traits applied and a starting frame set. Dynamic Type and color scheme are
/// applied through the SwiftUI environment (so measurement reflects them) and
/// mirrored onto UIKit trait overrides (for any embedded UIKit); increased
/// contrast — which SwiftUI can't set — is a trait override only. Intrinsic
/// components get only their width here; the pipeline measures their height
/// after the content settles.
///
/// SwiftUI transaction animations are disabled at the root: every state change
/// in the hosted tree commits its end state instantly instead of animating, so
/// finite time-based reveals no longer "run to completion" during settle — there
/// is no mid-flight frame to catch. The settle loop remains for `.task`-driven
/// async content, which still needs real suspension time to load.
@MainActor
private func makeHostingController(
    for view: some View,
    configuration: SnapshotConfiguration,
) -> UIViewController {
    let styled = view
        .environment(\.colorScheme, configuration.colorScheme)
        .dynamicTypeSize(configuration.dynamicType)
        .transaction {
            $0.disablesAnimations = true
            $0.animation = nil
        }
    let hostingController = UIHostingController(rootView: styled)
    hostingController.view.backgroundColor = .clear

    let traits = configuration.uiTraitCollection
    hostingController.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
    hostingController.traitOverrides.preferredContentSizeCategory = traits
        .preferredContentSizeCategory
    hostingController.traitOverrides.accessibilityContrast = traits.accessibilityContrast

    switch configuration.device.size {
        case let .fixed(size):
            hostingController.view.frame = CGRect(origin: .zero, size: size)
        case let .intrinsic(maxWidth):
            let width = maxWidth ?? UIScreen.main.bounds.width
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        case let .fullContent(width):
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
    }

    return hostingController
}
