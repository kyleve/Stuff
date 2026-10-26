import SwiftUI

extension SnapshotConfiguration {
    /// Expands the Cartesian product of the given axes into a matrix of
    /// configurations. An empty axis falls back to that axis's default singleton
    /// (light color scheme, `.large` Dynamic Type, standard contrast, the
    /// component frame, a standard capture), so a caller varies only the axes it
    /// cares about. An empty layout-traits axis inherits the host traits.
    public static func combinations(
        devices: [Frame] = [],
        colorSchemes: [ColorScheme] = [],
        dynamicTypes: [DynamicTypeSize] = [],
        contrasts: [ColorSchemeContrast] = [],
        layoutDirections: [LayoutDirection] = [],
        legibilityWeights: [LegibilityWeight] = [],
        layoutTraits requestedLayoutTraits: [LayoutTraits] = [],
        snapshotTypes: [SnapshotType] = [],
    ) -> [SnapshotConfiguration] {
        let devices = devices.isEmpty ? [.component] : devices
        let colorSchemes = colorSchemes.isEmpty ? [.light] : colorSchemes
        let dynamicTypes = dynamicTypes.isEmpty ? [.large] : dynamicTypes
        let contrasts = contrasts.isEmpty ? [.standard] : contrasts
        let layoutDirections = layoutDirections.isEmpty ? [.leftToRight] : layoutDirections
        let legibilityWeights = legibilityWeights.isEmpty ? [.regular] : legibilityWeights
        let layoutTraits: [LayoutTraits?] = requestedLayoutTraits.isEmpty
            ? [nil]
            : requestedLayoutTraits.map(Optional.some)
        let snapshotTypes = snapshotTypes.isEmpty ? [.standard] : snapshotTypes

        var result: [SnapshotConfiguration] = []
        for device in devices {
            for colorScheme in colorSchemes {
                for dynamicType in dynamicTypes {
                    for contrast in contrasts {
                        for layoutDirection in layoutDirections {
                            for legibilityWeight in legibilityWeights {
                                for layoutTraits in layoutTraits {
                                    for snapshotType in snapshotTypes {
                                        result.append(
                                            SnapshotConfiguration(
                                                colorScheme: colorScheme,
                                                dynamicType: dynamicType,
                                                contrast: contrast,
                                                layoutDirection: layoutDirection,
                                                legibilityWeight: legibilityWeight,
                                                layoutTraits: layoutTraits,
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
        }
        return result
    }
}

extension [SnapshotConfiguration] {
    /// The representative matrix for a component: the light/large/standard baseline plus
    /// one variant each for dark, an accessibility Dynamic Type size, increased
    /// contrast, and a VoiceOver-annotated capture — all at the component frame.
    ///
    /// Additive (not a full Cartesian product) so the image count stays
    /// proportional to the number of axes, not their product.
    public static var componentRepresentative: Self {
        representative(devices: [.component])
    }

    /// The representative matrix for a full screen: the same trait set as
    /// ``componentRepresentative`` across both an iPhone and an iPad frame.
    public static var screenRepresentative: Self {
        representative(devices: [.iPhone, .iPad])
    }

    /// The representative full-screen trait matrix at iPhone and iPad viewport sizes,
    /// with each frame growing beyond its device height when settled content is
    /// taller.
    public static var fullContentScreenRepresentative: Self {
        representative(devices: [.iPhoneFullContent, .iPadFullContent])
    }

    private static func representative(devices: [SnapshotConfiguration.Frame]) -> Self {
        SnapshotConfiguration.combinations(devices: devices)
            + SnapshotConfiguration.combinations(devices: devices, colorSchemes: [.dark])
            + SnapshotConfiguration.combinations(devices: devices, dynamicTypes: [.accessibility5])
            + SnapshotConfiguration.combinations(devices: devices, contrasts: [.increased])
            + SnapshotConfiguration.combinations(devices: devices, snapshotTypes: [.accessibility])
    }
}

extension [SnapshotConfiguration] {
    /// Light + dark at an iPhone frame — the compact matrix for the extra
    /// states in a multi-state screen loop (the representative state carries
    /// the full ``screenRepresentative``).
    public static var phoneLightDark: Self {
        SnapshotConfiguration.combinations(devices: [.iPhone], colorSchemes: [.light, .dark])
    }

    /// Light + dark at an intrinsic-height iPhone-width frame — the compact
    /// matrix for extra states on a full-content screen.
    public static var fullContentPhoneLightDark: Self {
        SnapshotConfiguration.combinations(
            devices: [.iPhoneFullContent],
            colorSchemes: [.light, .dark],
        )
    }

    /// Light + dark at the component frame — the compact matrix for the extra
    /// states in a sheet/component/widget loop.
    public static var componentLightDark: Self {
        SnapshotConfiguration.combinations(colorSchemes: [.light, .dark])
    }
}
