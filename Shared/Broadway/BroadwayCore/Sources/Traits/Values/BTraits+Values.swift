//
//  BTraits+Values.swift
//  BroadwayCore
//
//  Created by Kyle Van Essen on 3/31/26.
//

import Foundation
import UIKit

extension BTraits {
    public var mode: BMode {
        get { self[BMode.self] }
        set { self[BMode.self] = newValue }
    }

    public var contentSizeCategory: BContentSizeCategory {
        get { self[BContentSizeCategory.self] }
        set { self[BContentSizeCategory.self] = newValue }
    }
}

extension BTraits.Overrides {
    public var mode: BMode? {
        get { self[BMode.self] }
        set { self[BMode.self] = newValue }
    }

    public var contentSizeCategory: BContentSizeCategory? {
        get { self[BContentSizeCategory.self] }
        set { self[BContentSizeCategory.self] = newValue }
    }
}

public enum BMode: Equatable, Hashable, Sendable {
    case dark
    case light

    public static func from(_ style: UIUserInterfaceStyle) -> BMode {
        switch style {
            case .dark:
                .dark
            case .light, .unspecified:
                .light
            @unknown default:
                .light
        }
    }
}

extension BMode: BTraitsValue {
    public static let defaultValue: BMode = .light

    @MainActor public static func currentValue(from viewController: UIViewController) -> BMode {
        .from(viewController.traitCollection.userInterfaceStyle)
    }

    @MainActor public static func makeObserver(
        with viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (BMode) -> Void,
    ) -> UIViewControllerTraitObserver {
        UIViewControllerTraitObserver(
            observing: [UITraitUserInterfaceStyle.self],
            on: viewController,
        ) { vc in
            onChange(currentValue(from: vc))
        }
    }
}

public enum BContentSizeCategory: Equatable, Hashable, Comparable, Sendable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
    case extraExtraLarge
    case extraExtraExtraLarge
    case accessibilityMedium
    case accessibilityLarge
    case accessibilityExtraLarge
    case accessibilityExtraExtraLarge
    case accessibilityExtraExtraExtraLarge

    public var isAccessibilitySize: Bool {
        self >= Self.accessibilityMedium
    }
}

extension BContentSizeCategory: BTraitsValue {
    public static let defaultValue: BContentSizeCategory = .large

    @MainActor public static func currentValue(from viewController: UIViewController) -> BContentSizeCategory {
        .from(viewController.traitCollection.preferredContentSizeCategory)
    }

    @MainActor public static func makeObserver(
        with viewController: UIViewController,
        onChange: @MainActor @escaping @Sendable (BContentSizeCategory) -> Void,
    ) -> UIViewControllerTraitObserver {
        UIViewControllerTraitObserver(
            observing: [UITraitPreferredContentSizeCategory.self],
            on: viewController,
        ) { vc in
            onChange(currentValue(from: vc))
        }
    }

    public static func from(_ uiCategory: UIContentSizeCategory) -> BContentSizeCategory {
        switch uiCategory {
            case .extraSmall: .extraSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .extraLarge: .extraLarge
            case .extraExtraLarge: .extraExtraLarge
            case .extraExtraExtraLarge: .extraExtraExtraLarge
            case .accessibilityMedium: .accessibilityMedium
            case .accessibilityLarge: .accessibilityLarge
            case .accessibilityExtraLarge: .accessibilityExtraLarge
            case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
            case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
            default: .large
        }
    }
}
