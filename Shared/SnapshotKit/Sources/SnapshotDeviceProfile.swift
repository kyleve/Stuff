import CoreGraphics
import Foundation

extension SnapshotConfiguration {
    /// Representative device viewports. Dimensions come from simulator display profiles;
    /// safe areas and size classes are authored layout fixtures, not native measurements.
    public enum DeviceProfile: String, CaseIterable, Identifiable, Sendable {
        case iPhoneSE
        case iPhone17
        case iPhone17ProMax
        case iPadMini
        case iPadPro11
        case iPadPro13

        public enum Orientation: String, CaseIterable, Identifiable, Sendable {
            case portrait
            case landscape

            public var id: Self {
                self
            }

            public var title: String {
                switch self {
                    case .portrait: String(localized: .devicePortrait)
                    case .landscape: String(localized: .deviceLandscape)
                }
            }
        }

        public var id: Self {
            self
        }

        public var title: String {
            switch self {
                case .iPhoneSE: String(localized: .devicePhoneSmall)
                case .iPhone17: String(localized: .devicePhoneStandard)
                case .iPhone17ProMax: String(localized: .devicePhoneLarge)
                case .iPadMini: String(localized: .deviceTabletMini)
                case .iPadPro11: String(localized: .deviceTablet11)
                case .iPadPro13: String(localized: .deviceTablet13)
            }
        }

        public var idiom: Frame.LayoutTraits.InterfaceIdiom {
            switch self {
                case .iPhoneSE, .iPhone17, .iPhone17ProMax: .phone
                case .iPadMini, .iPadPro11, .iPadPro13: .pad
            }
        }

        public func frame(orientation: Orientation) -> Frame {
            let portraitSize = switch self {
                case .iPhoneSE: CGSize(width: 375, height: 667)
                case .iPhone17: CGSize(width: 402, height: 874)
                case .iPhone17ProMax: CGSize(width: 440, height: 956)
                case .iPadMini: CGSize(width: 744, height: 1133)
                case .iPadPro11: CGSize(width: 834, height: 1210)
                case .iPadPro13: CGSize(width: 1032, height: 1376)
            }
            let isLandscape = orientation == .landscape
            let isTablet = idiom == .pad
            let insets: Frame.Insets
            switch self {
                case .iPhoneSE:
                    insets = .init(top: isLandscape ? 0 : 20, leading: 0, bottom: 0, trailing: 0)
                case .iPhone17, .iPhone17ProMax:
                    // Reuse the existing notched-phone fixture's portrait margins.
                    let portrait = Frame.iPhoneNotched.safeAreaInsets
                    insets = isLandscape
                        ? .init(top: 0, leading: portrait.top, bottom: 21, trailing: portrait.top)
                        : portrait
                case .iPadMini, .iPadPro11, .iPadPro13:
                    insets = .init(top: 24, leading: 0, bottom: 20, trailing: 0)
            }
            return .viewport(
                name: rawValue + "-" + orientation.rawValue,
                size: isLandscape
                    ? CGSize(width: portraitSize.height, height: portraitSize.width)
                    : portraitSize,
                safeAreaInsets: insets,
                layoutTraits: .init(
                    horizontalSizeClass: isTablet || (self == .iPhone17ProMax && isLandscape)
                        ? .regular : .compact,
                    verticalSizeClass: isTablet || !isLandscape ? .regular : .compact,
                    interfaceIdiom: idiom,
                ),
            )
        }
    }
}
