import UIKit

/// The vertical space available to a component. Unspecified preserves an unknown system value.
public enum BVerticalSizeClass: Hashable, Sendable {
    case unspecified
    case compact
    case regular

    public init(_ sizeClass: UIUserInterfaceSizeClass) {
        self = switch sizeClass {
            case .unspecified: .unspecified
            case .compact: .compact
            case .regular: .regular
            @unknown default: .unspecified
        }
    }
}

extension BVerticalSizeClass: BTraitsValue {
    public static let defaultValue: Self = .unspecified

    @MainActor public static func currentValue(from viewController: UIViewController) -> Self {
        Self(viewController.traitCollection.verticalSizeClass)
    }

    @MainActor public static func makeObserver(
        with viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (Self) -> Void,
    ) -> UIViewControllerTraitObserver {
        UIViewControllerTraitObserver(
            observing: [UITraitVerticalSizeClass.self],
            on: viewController,
        ) { controller in
            onChange(currentValue(from: controller))
        }
    }
}

extension BTraits {
    public var verticalSizeClass: BVerticalSizeClass {
        get { self[BVerticalSizeClass.self] }
        set { self[BVerticalSizeClass.self] = newValue }
    }
}

extension BTraits.Overrides {
    public var verticalSizeClass: BVerticalSizeClass? {
        get { self[BVerticalSizeClass.self] }
        set { self[BVerticalSizeClass.self] = newValue }
    }
}
