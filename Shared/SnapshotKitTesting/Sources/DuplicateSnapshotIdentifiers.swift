import SnapshotKit

/// The full reference-image identifier for one rendered variant: the case name
/// and the configuration's identifier, underscore-joined, with empty segments
/// omitted. This is the exact name `assertSnapshots` records references under,
/// so the duplicate guard sees the same collisions the disk would.
func fullSnapshotIdentifier(
    caseName: String,
    configuration: SnapshotConfiguration,
) -> String {
    [caseName, configuration.identifier]
        .filter { !$0.isEmpty }
        .joined(separator: "_")
}

/// The full reference-image identifiers that more than one case × configuration
/// of `cases` would render to, sorted for stable messages. A collision means two
/// variants share one reference image: whichever records first, the other
/// silently compares against it — so the runner refuses to assert anything and
/// names the collisions instead (see `assertSnapshots(of:)`).
public func duplicateSnapshotIdentifiers(in cases: [SnapshotCase]) -> [String] {
    var occurrences: [String: Int] = [:]
    for snapshotCase in cases {
        for configuration in snapshotCase.configurations {
            let identifier = fullSnapshotIdentifier(
                caseName: snapshotCase.name,
                configuration: configuration,
            )
            let path = snapshotReferenceURL(
                testFilePath: "/Snapshots.swift",
                testName: "snapshot",
                identifier: identifier,
                configuration: configuration,
                referenceGroup: snapshotCase.referenceGroup,
            )
            let key = path.path.replacingOccurrences(of: "/__Snapshots__/Snapshots/", with: "")
                .replacingOccurrences(of: "snapshot.", with: "")
                .replacingOccurrences(of: ".png", with: "")
            occurrences[key, default: 0] += 1
        }
    }
    return occurrences.filter { $0.value > 1 }.keys.sorted()
}
