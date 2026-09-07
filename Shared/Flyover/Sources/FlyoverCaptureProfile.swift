#if DEBUG
    import CoreGraphics
    import SnapshotKit
    import SwiftUI

    /// One additive device and accessibility profile for a static export.
    public enum FlyoverCaptureProfile: String, CaseIterable, Codable, Identifiable, Sendable {
        case phoneLight = "phone-light"
        case phoneDark = "phone-dark"
        case tabletLight = "tablet-light"
        case phoneLandscape = "phone-landscape"
        case phoneSmall = "phone-small"
        case phoneXXXL = "phone-xxxl"
        case phoneAX3 = "phone-ax3"
        case phoneContrast = "phone-contrast"
        case phoneRTL = "phone-rtl"
        case phoneBold = "phone-bold"
        case phoneVoiceOver = "phone-voiceover"

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
                case .phoneLight: "Phone Light"
                case .phoneDark: "Phone Dark"
                case .tabletLight: "Tablet Light"
                case .phoneLandscape: "Phone Landscape"
                case .phoneSmall: "Phone Small Text"
                case .phoneXXXL: "Phone XXXL Text"
                case .phoneAX3: "Phone Accessibility 3"
                case .phoneContrast: "Phone Increased Contrast"
                case .phoneRTL: "Phone Right to Left"
                case .phoneBold: "Phone Bold Text"
                case .phoneVoiceOver: "Phone VoiceOver"
            }
        }

        public static func parse(_ identifiers: [String]) throws -> [Self] {
            try orderedUnique(identifiers.map { identifier in
                guard let profile = Self(rawValue: identifier) else {
                    throw FlyoverExportError.unknownProfile(identifier)
                }
                return profile
            })
        }

        static func orderedUnique(_ requestedProfiles: [Self]) -> [Self] {
            let profiles = requestedProfiles.isEmpty ? [.phoneLight, .phoneDark] : requestedProfiles
            var seen: Set<Self> = []
            return profiles.filter { seen.insert($0).inserted }
        }

        var deviceName: String {
            self == .tabletLight ? "tablet" : "phone"
        }

        var orientationName: String {
            self == .phoneLandscape ? "landscape" : "portrait"
        }

        var colorSchemeName: String {
            colorScheme == .dark ? "dark" : "light"
        }

        var dynamicTypeName: String {
            switch self {
                case .phoneSmall:
                    "small"
                case .phoneXXXL:
                    "xxxl"
                case .phoneAX3:
                    "accessibility3"
                case .phoneLight, .phoneDark, .tabletLight, .phoneLandscape,
                     .phoneContrast, .phoneRTL, .phoneBold, .phoneVoiceOver:
                    "large"
            }
        }

        var contrastName: String {
            contrast == .increased ? "increased" : "standard"
        }

        var layoutDirectionName: String {
            layoutDirection == .rightToLeft ? "right-to-left" : "left-to-right"
        }

        var legibilityWeightName: String {
            legibilityWeight == .bold ? "bold" : "regular"
        }

        var snapshotTypeName: String {
            snapshotType == .accessibility ? "accessibility" : "standard"
        }

        func configuration(
            viewport: FlyoverViewport,
            captureExtent: FlyoverCaptureExtent,
        ) -> SnapshotConfiguration {
            let baseSize = switch viewport {
                case .device: profileSize
                case let .fixed(size): size
            }
            let frame = switch captureExtent {
                case .viewport:
                    SnapshotConfiguration.Frame(name: rawValue, size: .fixed(baseSize))
                case .intrinsic:
                    SnapshotConfiguration.Frame(
                        name: rawValue,
                        size: .intrinsic(maxWidth: baseSize.width),
                    )
                case .fullContent:
                    SnapshotConfiguration.Frame.fullContent(
                        name: rawValue,
                        width: baseSize.width,
                        minimumHeight: baseSize.height,
                    )
                case .fullContent2D:
                    SnapshotConfiguration.Frame.fullContent2D(
                        name: rawValue,
                        minimumSize: baseSize,
                    )
            }
            return SnapshotConfiguration(
                colorScheme: colorScheme,
                dynamicType: dynamicType,
                contrast: contrast,
                layoutDirection: layoutDirection,
                legibilityWeight: legibilityWeight,
                device: frame,
                snapshotType: snapshotType,
            )
        }

        private var profileSize: CGSize {
            switch self {
                case .tabletLight:
                    CGSize(width: 834, height: 1194)
                case .phoneLandscape:
                    CGSize(width: 874, height: 402)
                case .phoneLight, .phoneDark, .phoneSmall, .phoneXXXL,
                     .phoneAX3, .phoneContrast, .phoneRTL, .phoneBold,
                     .phoneVoiceOver:
                    CGSize(width: 402, height: 874)
            }
        }

        private var colorScheme: ColorScheme {
            self == .phoneDark ? .dark : .light
        }

        private var dynamicType: DynamicTypeSize {
            switch self {
                case .phoneSmall: .small
                case .phoneXXXL: .xxxLarge
                case .phoneAX3: .accessibility3
                case .phoneLight, .phoneDark, .tabletLight, .phoneLandscape,
                     .phoneContrast, .phoneRTL, .phoneBold, .phoneVoiceOver:
                    .large
            }
        }

        private var contrast: ColorSchemeContrast {
            self == .phoneContrast ? .increased : .standard
        }

        private var layoutDirection: LayoutDirection {
            self == .phoneRTL ? .rightToLeft : .leftToRight
        }

        private var legibilityWeight: LegibilityWeight {
            self == .phoneBold ? .bold : .regular
        }

        private var snapshotType: SnapshotConfiguration.SnapshotType {
            self == .phoneVoiceOver ? .accessibility : .standard
        }
    }
#endif
