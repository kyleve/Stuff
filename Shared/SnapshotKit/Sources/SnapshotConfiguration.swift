import CoreGraphics
import SwiftUI

/// One rendering variant in a snapshot matrix: the appearance traits to apply,
/// the frame to render into, and whether the capture is standard or an
/// accessibility (VoiceOver-annotated) snapshot.
///
/// `Hashable` so it can key a matrix, and it vends an ``identifier`` (from
/// ``identifierParts``) that names the reference image. The identifier **omits
/// default axes** — only a non-default color scheme, Dynamic Type size, contrast,
/// snapshot type, or a named device shows up — so the common (light / large /
/// standard) baseline stays terse. Treat the omission rules as a wire format:
/// changing them renames every reference image on disk.
public struct SnapshotConfiguration: Hashable, Sendable {
    /// The color scheme (light/dark) to render in.
    public var colorScheme: ColorScheme
    /// The Dynamic Type size to render at.
    public var dynamicType: DynamicTypeSize
    /// The color-scheme contrast (standard / increased) to render with.
    public var contrast: ColorSchemeContrast
    /// The layout direction (left-to-right / right-to-left) to render in.
    public var layoutDirection: LayoutDirection
    /// The legibility weight (regular / bold text) to render with.
    public var legibilityWeight: LegibilityWeight
    /// The frame (size + name) to render into.
    public var device: Frame
    /// Whether this is a plain image or a VoiceOver-annotated accessibility image.
    public var snapshotType: SnapshotType
    /// An optional caller-supplied name that prefixes the identifier — for a
    /// one-off variant that the axes above don't already distinguish.
    public var name: String?

    public init(
        colorScheme: ColorScheme = .light,
        dynamicType: DynamicTypeSize = .large,
        contrast: ColorSchemeContrast = .standard,
        layoutDirection: LayoutDirection = .leftToRight,
        legibilityWeight: LegibilityWeight = .regular,
        device: Frame = .component,
        snapshotType: SnapshotType = .standard,
        name: String? = nil,
    ) {
        self.colorScheme = colorScheme
        self.dynamicType = dynamicType
        self.contrast = contrast
        self.layoutDirection = layoutDirection
        self.legibilityWeight = legibilityWeight
        self.device = device
        self.snapshotType = snapshotType
        self.name = name
    }

    /// The identifier segments for this configuration, omitting any axis at its
    /// default value. Joined into ``identifier``.
    public var identifierParts: [String] {
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append(name) }
        if !device.name.isEmpty { parts.append(device.name) }
        if colorScheme == .dark { parts.append("dark") }
        if dynamicType != .large { parts.append(dynamicType.snapshotToken) }
        if contrast == .increased { parts.append("contrast") }
        if layoutDirection == .rightToLeft { parts.append("rtl") }
        if legibilityWeight == .bold { parts.append("bold") }
        if snapshotType == .accessibility { parts.append("accessibility") }
        return parts
    }

    /// The reference-image name for this configuration (its non-default axes,
    /// underscore-joined). Empty for the plain light/large/standard baseline —
    /// the runner prefixes the enclosing case name so it is still distinct.
    public var identifier: String {
        identifierParts.joined(separator: "_")
    }
}

extension SnapshotConfiguration {
    /// Whether this configuration is a plain image or a VoiceOver-annotated one.
    public enum SnapshotType: Hashable, Sendable {
        case standard
        case accessibility
    }

    /// How a variant is sized, plus an optional short name that stands in for the
    /// size in identifiers (e.g. `iPhone` instead of `402x874`).
    public struct Frame: Hashable, Sendable {
        private static let iPhoneWidth: CGFloat = 402
        private static let iPhoneHeight: CGFloat = 874
        private static let iPadWidth: CGFloat = 834
        private static let iPadHeight: CGFloat = 1194

        /// The identifier token for this frame (`""` for the unnamed component
        /// frame, `iPhone`/`iPad` for device frames).
        public var name: String
        /// How the content is sized.
        public var size: SizeStrategy
        /// The minimum rendered height for a content-measured frame. `nil`
        /// allows the frame to shrink-wrap its content; fixed frames ignore it.
        public var minimumHeight: CGFloat?
        /// Simulated device safe-area insets applied at capture. `.zero` (the
        /// default) keeps images independent of any physical device's chrome;
        /// a preset like ``iPhoneNotched`` opts a case into rendering under
        /// notch/home-indicator insets.
        public var safeAreaInsets: Insets

        public init(
            name: String,
            size: SizeStrategy,
            minimumHeight: CGFloat? = nil,
            safeAreaInsets: Insets = .zero,
        ) {
            self.name = name
            self.size = size
            self.minimumHeight = minimumHeight
            self.safeAreaInsets = safeAreaInsets
        }

        /// Safe-area insets in points. A minimal `Hashable` value type so
        /// ``Frame`` stays hashable (UIKit's `UIEdgeInsets` is not).
        public struct Insets: Hashable, Sendable {
            public var top: CGFloat
            public var leading: CGFloat
            public var bottom: CGFloat
            public var trailing: CGFloat

            public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
                self.top = top
                self.leading = leading
                self.bottom = bottom
                self.trailing = trailing
            }

            public static let zero = Insets(top: 0, leading: 0, bottom: 0, trailing: 0)
        }

        /// A component frame: sized to fit its content, capped to a phone-width
        /// maximum so a component without an intrinsic width still measures.
        public static let component = Frame(name: "", size: .intrinsic(maxWidth: 402))
        /// A full-content frame: fixed width, height measured from the settled
        /// content — the whole scrollable content renders in one image, nothing
        /// scrolls. A `ScrollView` measured this way reports its content height,
        /// so wrapping scrollable content captures every row (lazy stacks
        /// materialize fully — at full-content height every row is visible).
        /// Production navigation, tab, sheet, search, and toolbar chrome stays
        /// wrapped around the full-width scrolling descendant that drives the
        /// measured height.
        ///
        /// `name` is the identifier token for the frame (conventionally
        /// `fullHeight`); it must stay stable once references are recorded.
        public static func fullContent(
            name: String,
            width: CGFloat,
            minimumHeight: CGFloat? = nil,
        ) -> Frame {
            Frame(
                name: name,
                size: .fullContent(width: width),
                minimumHeight: minimumHeight,
            )
        }

        /// An iPhone viewport that grows to fit settled scrolling content.
        public static let iPhoneFullContent = fullContent(
            name: "iPhone",
            width: iPhoneWidth,
            minimumHeight: iPhoneHeight,
        )

        /// An iPad viewport that grows to fit settled scrolling content.
        public static let iPadFullContent = fullContent(
            name: "iPad",
            width: iPadWidth,
            minimumHeight: iPadHeight,
        )

        /// A phone screen frame (iPhone 17 point size).
        public static let iPhone = Frame(
            name: "iPhone",
            size: .fixed(CGSize(width: iPhoneWidth, height: iPhoneHeight)),
        )
        /// A tablet screen frame (iPad Pro 11" portrait point size).
        public static let iPad = Frame(
            name: "iPad",
            size: .fixed(CGSize(width: iPadWidth, height: iPadHeight)),
        )
        /// The iPhone frame with simulated device insets (Dynamic Island top,
        /// home-indicator bottom), for cases that must prove layout under real
        /// device chrome rather than the inset-free default.
        public static let iPhoneNotched = Frame(
            name: "iPhoneNotched",
            size: .fixed(CGSize(width: iPhoneWidth, height: iPhoneHeight)),
            safeAreaInsets: Insets(top: 47, leading: 0, bottom: 34, trailing: 0),
        )
    }

    /// How a snapshot variant resolves its size.
    public enum SizeStrategy: Hashable, Sendable {
        /// Size to fit the content, optionally capped to a maximum width.
        case intrinsic(maxWidth: CGFloat?)
        /// A fixed point size (a device viewport).
        case fixed(CGSize)
        /// A fixed width with the height measured from the settled content, so
        /// scrollable content renders whole (see ``Frame/fullContent(name:width:)``).
        case fullContent(width: CGFloat)
    }
}

extension DynamicTypeSize {
    /// A short, stable token for identifiers. Only non-`.large` values ever reach
    /// a filename (the default is omitted), but the full map keeps tokens unique.
    var snapshotToken: String {
        switch self {
            case .xSmall: "xs"
            case .small: "sm"
            case .medium: "md"
            case .large: "lg"
            case .xLarge: "xl"
            case .xxLarge: "xxl"
            case .xxxLarge: "xxxl"
            case .accessibility1: "ax1"
            case .accessibility2: "ax2"
            case .accessibility3: "ax3"
            case .accessibility4: "ax4"
            case .accessibility5: "ax5"
            @unknown default: "unknown"
        }
    }
}
