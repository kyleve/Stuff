//
//  BTraitValues+SwiftUI.swift
//  BroadwayUI
//

import BroadwayCore
import SwiftUI

extension BMode {
    /// Maps a SwiftUI `ColorScheme` to a Broadway ``BMode``, so a SwiftUI root
    /// can seed the trait from `@Environment(\.colorScheme)` (the UIKit path
    /// uses ``from(_:)`` with `UIUserInterfaceStyle`).
    public init(_ colorScheme: ColorScheme) {
        switch colorScheme {
            case .dark: self = .dark
            case .light: self = .light
            @unknown default: self = .light
        }
    }
}

extension BContentSizeCategory {
    /// Maps a SwiftUI `DynamicTypeSize` to a Broadway ``BContentSizeCategory``,
    /// so a SwiftUI root can seed the trait from `@Environment(\.dynamicTypeSize)`
    /// (the UIKit path uses ``from(_:)`` with `UIContentSizeCategory`).
    public init(_ dynamicTypeSize: DynamicTypeSize) {
        switch dynamicTypeSize {
            case .xSmall: self = .extraSmall
            case .small: self = .small
            case .medium: self = .medium
            case .large: self = .large
            case .xLarge: self = .extraLarge
            case .xxLarge: self = .extraExtraLarge
            case .xxxLarge: self = .extraExtraExtraLarge
            case .accessibility1: self = .accessibilityMedium
            case .accessibility2: self = .accessibilityLarge
            case .accessibility3: self = .accessibilityExtraLarge
            case .accessibility4: self = .accessibilityExtraExtraLarge
            case .accessibility5: self = .accessibilityExtraExtraExtraLarge
            @unknown default: self = .large
        }
    }
}
