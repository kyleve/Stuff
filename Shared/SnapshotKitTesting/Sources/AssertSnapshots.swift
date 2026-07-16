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
@MainActor
public func assertSnapshots(
    of provider: (some SnapshotProviding).Type,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    for snapshotCase in provider.snapshots {
        assertSnapshots(
            of: snapshotCase.content,
            named: snapshotCase.name,
            configurations: snapshotCase.configurations,
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
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) {
    do {
        try waitFor { hostKeyWindow() != nil }
    } catch {
        Issue.record("Snapshot host window never appeared: \(error)")
        return
    }

    for configuration in configurations {
        let hostingController = makeHostingController(for: view, configuration: configuration)
        let identifier = [name, configuration.identifier]
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        assertSnapshot(
            of: hostingController,
            as: .snapshotKitImage(isAccessibility: configuration.snapshotType == .accessibility),
            named: identifier,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column,
        )
    }
}

/// Builds a hosting controller for `view` with the configuration's appearance
/// traits applied and its frame resolved (fixed device size, or measured to fit a
/// constrained width). Dynamic Type and color scheme are applied through the
/// SwiftUI environment (so measurement reflects them) and mirrored onto UIKit
/// trait overrides (for any embedded UIKit); increased contrast — which SwiftUI
/// can't set — is a trait override only.
@MainActor
private func makeHostingController(
    for view: some View,
    configuration: SnapshotConfiguration,
) -> UIViewController {
    let styled = view
        .environment(\.colorScheme, configuration.colorScheme)
        .dynamicTypeSize(configuration.dynamicType)
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
            let constrained = CGSize(width: width, height: .greatestFiniteMagnitude)
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
            hostingController.waitForStableSize(constrainedTo: constrained)
            var measured = hostingController.view.sizeThatFits(constrained)
            measured.width = width
            if !measured.height.isFinite || measured.height <= 0 {
                measured.height = 1
            }
            hostingController.view.frame = CGRect(origin: .zero, size: measured)
    }

    return hostingController
}
