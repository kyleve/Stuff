@_spi(Capture) import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import Testing

/// The fast gate keeps existing reference identities and partitions, rather than reduces, coverage.
@MainActor
protocol WhereThemeSnapshotGate: SnapshotProviding {
    static var lightDarkCases: Set<String> { get }
}

enum WhereLightDarkSnapshots<Source: WhereThemeSnapshotGate>: SnapshotProviding {
    static var snapshots: [SnapshotCase] {
        Source.partitionedSnapshots(lightDark: true)
    }
}

enum WhereExtendedSnapshots<Source: WhereThemeSnapshotGate>: SnapshotProviding {
    static var snapshots: [SnapshotCase] {
        Source.partitionedSnapshots(lightDark: false)
    }
}

extension WhereThemeSnapshotGate {
    fileprivate static func partitionedSnapshots(lightDark: Bool) -> [SnapshotCase] {
        snapshots.compactMap { snapshot in
            let configurations = snapshot.configurations.filter { configuration in
                let baseline = lightDarkCases.contains(snapshot.name)
                    && configuration.snapshotType == .standard
                    && configuration.dynamicType == .large
                    && configuration.contrast == .standard
                    && configuration.layoutDirection == .leftToRight
                    && configuration.legibilityWeight == .regular
                    && configuration.layoutTraits == nil
                    && configuration.name == nil
                    && ["", "iPhone"].contains(configuration.device.name)
                return baseline == lightDark
            }
            guard !configurations.isEmpty else { return nil }
            return snapshot.withThemeConfigurations(configurations)
        }
    }
}

@MainActor
func assertThemeSnapshot(
    _ snapshot: SnapshotCase,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
) async {
    if case let .single(content) = snapshot.capture {
        await assertSnapshots(
            of: content(),
            named: snapshot.name,
            configurations: snapshot.configurations,
            referenceGroup: snapshot.referenceGroup,
            measurementReadiness: snapshot.measurementReadiness,
            onReadyToMeasure: snapshot.onReadyToMeasure,
            settle: snapshot.settle,
            onReadyToSnapshot: snapshot.onReadyToSnapshot,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column,
        )
    } else { Issue.record(
        "Expected one production screen",
        sourceLocation: .init(
            fileID: String(describing: fileID),
            filePath: String(describing: file),
            line: Int(line),
            column: Int(column),
        ),
    ) }
}

extension SnapshotCase {
    /// Shares the production fixture and capture hooks across the two validation gates.
    @MainActor func withThemeConfigurations(_ configurations: [SnapshotConfiguration]) -> Self {
        switch capture {
            case let .single(content):
                SnapshotCase(
                    name: name,
                    configurations: configurations,
                    referenceGroup: referenceGroup,
                    measurementReadiness: measurementReadiness,
                    onReadyToMeasure: onReadyToMeasure,
                    settle: settle,
                    onReadyToSnapshot: onReadyToSnapshot,
                ) { content() }
            case let .cutsheet(collection):
                .cutsheet(
                    name: name,
                    configurations: configurations,
                    referenceGroup: referenceGroup,
                    measurementReadiness: measurementReadiness,
                    onReadyToMeasure: onReadyToMeasure,
                    settle: settle,
                    onReadyToSnapshot: onReadyToSnapshot,
                ) { for panel in collection.panels {
                    panel
                } }
        }
    }
}
