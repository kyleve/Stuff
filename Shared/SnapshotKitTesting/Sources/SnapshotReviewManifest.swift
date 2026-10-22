import Foundation
import SnapshotKit
import SnapshotReviewCore
import SwiftUI

/// Exports exact case boundaries without changing the reference filename contract.
enum SnapshotReviewManifest {
    static func entry(
        reference: URL,
        testName: String,
        caseName: String,
        configuration: SnapshotConfiguration,
    ) throws -> SnapshotManifest.Entry {
        let suite = try suiteURL(reference)
        let path = try SnapshotPath(String(reference.path.dropFirst(suite.path.count + 1)))
        let traits = configuration.layoutTraits.map {
            let idiom = switch $0.interfaceIdiom {
                case .phone: "phone"
                case .tablet: "tablet"
            }
            return "\(idiom)-\(sizeClassName($0.horizontalSizeClass))-\(sizeClassName($0.verticalSizeClass))"
        }
        return SnapshotManifest.Entry(
            path: path,
            testName: testName,
            caseName: caseName,
            configurationIdentifier: configuration.identifier,
            frame: configuration.device.name.isEmpty ? "Component" : configuration.device.name,
            configurationName: configuration.name,
            layoutTraits: traits,
            variant: SnapshotVariant(
                colorScheme: configuration.colorScheme == .dark ? .dark : .light,
                dynamicType: dynamicTypeName(configuration.dynamicType),
                increasedContrast: configuration.contrast == .increased,
                rightToLeft: configuration.layoutDirection == .rightToLeft,
                bold: configuration.legibilityWeight == .bold,
                accessibility: configuration.snapshotType == .accessibility,
            ),
        )
    }

    static func write(
        reference: URL,
        testName: String,
        caseName: String,
        configuration: SnapshotConfiguration,
    ) throws {
        let suite = try suiteURL(reference)
        try ReviewFileStore.updateManifest(
            entry(
                reference: reference,
                testName: testName,
                caseName: caseName,
                configuration: configuration,
            ),
            suite: suite,
        )
    }

    private static func suiteURL(_ reference: URL) throws -> URL {
        let components = reference.pathComponents
        guard let marker = components.lastIndex(of: "__Snapshots__"), marker + 2 < components.count
        else { throw ReviewError.invalidDocument("The reference must be inside a snapshot suite.") }
        return URL(
            fileURLWithPath: NSString.path(withComponents: Array(components.prefix(marker + 2))),
            isDirectory: true,
        )
    }

    private static func sizeClassName(_ size: SnapshotConfiguration.LayoutTraits
        .SizeClass) -> String
    {
        switch size {
            case .compact: "compact"
            case .regular: "regular"
        }
    }

    private static func dynamicTypeName(_ size: DynamicTypeSize) -> String {
        switch size {
            case .xSmall: "xSmall"
            case .small: "small"
            case .medium: "medium"
            case .large: "large"
            case .xLarge: "xLarge"
            case .xxLarge: "xxLarge"
            case .xxxLarge: "xxxLarge"
            case .accessibility1: "accessibility1"
            case .accessibility2: "accessibility2"
            case .accessibility3: "accessibility3"
            case .accessibility4: "accessibility4"
            case .accessibility5: "accessibility5"
            @unknown default: "unknown"
        }
    }
}
