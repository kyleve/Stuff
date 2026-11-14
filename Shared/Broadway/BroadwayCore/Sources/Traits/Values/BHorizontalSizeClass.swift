import UIKit

/// The horizontal space available to a component. Unavailable system values use compact styling.
public enum BHorizontalSizeClass: Hashable, Sendable {
    case compact
    case regular

    public init(_ sizeClass: UIUserInterfaceSizeClass) {
        self = switch sizeClass {
            case .unspecified: .compact
            case .compact: .compact
            case .regular: .regular
            @unknown default: .compact
        }
    }
}

extension BHorizontalSizeClass: BTraitsValue {
    public static let defaultValue: Self = .compact

    @MainActor public static func currentValue(from viewController: UIViewController) -> Self {
        Self(viewController.traitCollection.horizontalSizeClass)
    }

    @MainActor public static func makeObserver(
        with viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (Self) -> Void,
    ) -> UIViewControllerTraitObserver {
        UIViewControllerTraitObserver(
            observing: [UITraitHorizontalSizeClass.self],
            on: viewController,
        ) { controller in
            onChange(currentValue(from: controller))
        }
    }
}

extension BTraits {
    public var horizontalSizeClass: BHorizontalSizeClass {
        get { self[BHorizontalSizeClass.self] }
        set { self[BHorizontalSizeClass.self] = newValue }
    }
}

extension BTraits.Overrides {
    public var horizontalSizeClass: BHorizontalSizeClass? {
        get { self[BHorizontalSizeClass.self] }
        set { self[BHorizontalSizeClass.self] = newValue }
    }
}
