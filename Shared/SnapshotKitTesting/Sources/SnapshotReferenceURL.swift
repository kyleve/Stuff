import Foundation
import SnapshotKit

/// Resolves the reference shared by recording, comparison, and diff reports.
///
/// Standard captures with non-default text, contrast, direction, or weight use
/// the selected reference group's `other` directory. Accessibility annotations always stay beside
/// the ordinary light/dark references, regardless of their other traits.
/// Filename sanitization matches swift-snapshot-testing; round-trip tests guard
/// that coupling without changing the configuration's stable identifier.
@_spi(Testing) public func snapshotReferenceURL(
    testFilePath: String,
    testName: String,
    identifier: String,
    configuration: SnapshotConfiguration,
    referenceGroup: SnapshotReferenceGroup? = nil,
) -> URL {
    let testFile = URL(fileURLWithPath: testFilePath)
    var directory = testFile
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent(testFile.deletingPathExtension().lastPathComponent)
    if let referenceGroup { directory.appendPathComponent(referenceGroup.rawValue) }
    if configuration.snapshotType == .standard,
       configuration.dynamicType != .large
       || configuration.contrast == .increased
       || configuration.layoutDirection == .rightToLeft
       || configuration.legibilityWeight == .bold
    {
        directory.appendPathComponent("other")
    }
    return directory.appendingPathComponent(
        "\(sanitizePathComponent(testName)).\(sanitizePathComponent(identifier)).png",
    )
}

private func sanitizePathComponent(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
}
