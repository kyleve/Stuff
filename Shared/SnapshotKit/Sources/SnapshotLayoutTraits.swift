import SwiftUI
import UIKit

extension SnapshotConfiguration.Frame {
    /// Explicit container traits. Frame dimensions alone do not set UIKit's idiom or size classes.
    public struct LayoutTraits: Hashable, Sendable {
        public var horizontalSizeClass: SizeClass
        public var verticalSizeClass: SizeClass
        public var interfaceIdiom: InterfaceIdiom

        public init(
            horizontalSizeClass: SizeClass,
            verticalSizeClass: SizeClass,
            interfaceIdiom: InterfaceIdiom,
        ) {
            self.horizontalSizeClass = horizontalSizeClass
            self.verticalSizeClass = verticalSizeClass
            self.interfaceIdiom = interfaceIdiom
        }

        public enum SizeClass: Hashable, Sendable {
            case compact
            case regular

            public var uiSizeClass: UIUserInterfaceSizeClass {
                switch self {
                    case .compact: .compact
                    case .regular: .regular
                }
            }

            public var swiftUISizeClass: UserInterfaceSizeClass {
                switch self {
                    case .compact: .compact
                    case .regular: .regular
                }
            }
        }

        public enum InterfaceIdiom: Hashable, Sendable {
            case phone
            case pad

            public var uiIdiom: UIUserInterfaceIdiom {
                switch self {
                    case .phone: .phone
                    case .pad: .pad
                }
            }
        }

        public static let phonePortrait = Self(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            interfaceIdiom: .phone,
        )

        public static let phoneLandscape = Self(
            horizontalSizeClass: .compact,
            verticalSizeClass: .compact,
            interfaceIdiom: .phone,
        )

        public static let tablet = Self(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            interfaceIdiom: .pad,
        )
    }
}

extension View {
    /// Sets only explicitly configured layout traits; component frames inherit their container.
    public func snapshotLayoutTraits(_ configuration: SnapshotConfiguration) -> some View {
        transformEnvironment(\.horizontalSizeClass) { value in
            if let traits = configuration.device.layoutTraits {
                value = traits.horizontalSizeClass.swiftUISizeClass
            }
        }
        .transformEnvironment(\.verticalSizeClass) { value in
            if let traits = configuration.device.layoutTraits {
                value = traits.verticalSizeClass.swiftUISizeClass
            }
        }
    }
}
