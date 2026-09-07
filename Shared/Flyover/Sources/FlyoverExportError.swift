#if DEBUG
    import Foundation

    /// A structural, capture, or artifact error from a static export.
    public enum FlyoverExportError: Error, Equatable, Sendable {
        case invalidCatalog(issueCount: Int)
        case emptyApplicationIdentifier
        case emptyScreenIdentifier(screenTitle: String)
        case duplicateScreenIdentifier(String)
        case emptyVariantIdentifier(screen: String)
        case duplicateVariantIdentifier(screen: String, variant: String)
        case mixedSizingPolicy(screen: String, variant: String, extents: [String])
        case missingManifestGeometry(kind: String, identifier: String)
        case unknownProfile(String)
        case captureFailed(
            group: String,
            screen: String,
            variant: String,
            profile: String,
            phase: String,
            reason: String,
        )
        case emptyPNG(screen: String, variant: String, profile: String)
        case assetCountMismatch(expected: Int, actual: Int)
        case outputWriteFailed(path: String, reason: String)
    }

    extension FlyoverExportError: LocalizedError {
        public var errorDescription: String? {
            switch self {
                case let .invalidCatalog(issueCount):
                    "The Flyover catalog has \(issueCount) validation errors."
                case .emptyApplicationIdentifier:
                    "The export application identifier is empty."
                case let .emptyScreenIdentifier(screenTitle):
                    "The export identifier for \(screenTitle) is empty."
                case let .duplicateScreenIdentifier(identifier):
                    "The screen export identifier \(identifier) is not unique."
                case let .emptyVariantIdentifier(screen):
                    "A variant export identifier is empty in \(screen)."
                case let .duplicateVariantIdentifier(screen, variant):
                    "The variant export identifier \(variant) is not unique in \(screen)."
                case let .mixedSizingPolicy(screen, variant, extents):
                    "The export policy for \(screen) / \(variant) mixes sizing classes: \(extents.joined(separator: ", "))."
                case let .missingManifestGeometry(kind, identifier):
                    "The Flyover layout has no \(kind) geometry for \(identifier)."
                case let .unknownProfile(identifier):
                    "The Flyover capture profile \(identifier) is unknown."
                case let .captureFailed(group, screen, variant, profile, phase, reason):
                    "The Flyover export failed during \(phase) for \(group) / \(screen) / \(variant) / \(profile): \(reason)"
                case let .emptyPNG(screen, variant, profile):
                    "The capture for \(screen) / \(variant) / \(profile) returned an empty PNG."
                case let .assetCountMismatch(expected, actual):
                    "The Flyover artifact contains \(actual) images. The manifest requires \(expected)."
                case let .outputWriteFailed(path, reason):
                    "The Flyover exporter could not write \(path): \(reason)"
            }
        }
    }
#endif
