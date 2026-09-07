import SwiftUI

extension SnapshotConfiguration {
    /// Expands the Cartesian product of the given axes into a matrix of
    /// configurations. An empty axis falls back to that axis's default singleton
    /// (light color scheme, `.large` Dynamic Type, standard contrast, the
    /// component frame, a standard capture), so a caller varies only the axes it
    /// cares about.
    public static func combinations(
        devices: [Frame] = [],
        colorSchemes: [ColorScheme] = [],
        dynamicTypes: [DynamicTypeSize] = [],
        contrasts: [ColorSchemeContrast] = [],
        layoutDirections: [LayoutDirection] = [],
        legibilityWeights: [LegibilityWeight] = [],
        snapshotTypes: [SnapshotType] = [],
    ) -> [SnapshotConfiguration] {
        let devices = devices.isEmpty ? [.component] : devices
        let colorSchemes = colorSchemes.isEmpty ? [.light] : colorSchemes
        let dynamicTypes = dynamicTypes.isEmpty ? [.large] : dynamicTypes
        let contrasts = contrasts.isEmpty ? [.standard] : contrasts
        let layoutDirections = layoutDirections.isEmpty ? [.leftToRight] : layoutDirections
        let legibilityWeights = legibilityWeights.isEmpty ? [.regular] : legibilityWeights
        let snapshotTypes = snapshotTypes.isEmpty ? [.standard] : snapshotTypes

        var result: [SnapshotConfiguration] = []
        for device in devices {
            for colorScheme in colorSchemes {
                for dynamicType in dynamicTypes {
                    for contrast in contrasts {
                        for layoutDirection in layoutDirections {
                            for legibilityWeight in legibilityWeights {
                                for snapshotType in snapshotTypes {
                                    result.append(
                                        SnapshotConfiguration(
                                            colorScheme: colorScheme,
                                            dynamicType: dynamicType,
                                            contrast: contrast,
                                            layoutDirection: layoutDirection,
                                            legibilityWeight: legibilityWeight,
                                            device: device,
                                            snapshotType: snapshotType,
                                        ),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        return result
    }
}

extension [SnapshotConfiguration] {
    /// The default matrix for a component: the light/large/standard baseline plus
    /// one variant each for dark, an accessibility Dynamic Type size, increased
    /// contrast, and a VoiceOver-annotated capture — all at the component frame.
    ///
    /// Additive (not a full Cartesian product) so the image count stays
    /// proportional to the number of axes, not their product.
    public static var componentDefaults: Self {
        defaults(devices: [.component])
    }

    /// The default matrix for a full screen: the same trait set as
    /// ``componentDefaults`` across both an iPhone and an iPad frame.
    public static var screenDefaults: Self {
        defaults(devices: [.iPhone, .iPad])
    }

    /// The default full-screen trait matrix at iPhone and iPad viewport sizes,
    /// with each frame growing beyond its device height when settled content is
    /// taller.
    public static var fullContentScreenDefaults: Self {
        defaults(devices: [.iPhoneFullContent, .iPadFullContent])
    }

    private static func defaults(devices: [SnapshotConfiguration.Frame]) -> Self {
        SnapshotConfiguration.combinations(devices: devices)
            + SnapshotConfiguration.combinations(devices: devices, colorSchemes: [.dark])
            + SnapshotConfiguration.combinations(devices: devices, dynamicTypes: [.accessibility5])
            + SnapshotConfiguration.combinations(devices: devices, contrasts: [.increased])
            + SnapshotConfiguration.combinations(devices: devices, snapshotTypes: [.accessibility])
    }
}
