import SnapshotKit
import SwiftUI
import UIKit

/// Builds a host with the configuration's SwiftUI and UIKit traits.
@MainActor
func makeHostingController(
    for view: some View,
    configuration: SnapshotConfiguration,
) -> UIViewController {
    let styled = view
        .environment(\.colorScheme, configuration.colorScheme)
        .dynamicTypeSize(configuration.dynamicType)
        .environment(\.layoutDirection, configuration.layoutDirection)
        .environment(\.legibilityWeight, configuration.legibilityWeight)
        .transaction {
            $0.disablesAnimations = true
            $0.animation = nil
        }
    let hostingController = UIHostingController(rootView: styled)
    hostingController.view.backgroundColor = .clear

    let traits = configuration.uiTraitCollection
    hostingController.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
    hostingController.traitOverrides.preferredContentSizeCategory = traits
        .preferredContentSizeCategory
    hostingController.traitOverrides.accessibilityContrast = traits.accessibilityContrast
    hostingController.traitOverrides.layoutDirection = traits.layoutDirection
    hostingController.traitOverrides.legibilityWeight = traits.legibilityWeight

    switch configuration.device.size {
        case let .fixed(size):
            hostingController.view.frame = CGRect(origin: .zero, size: size)
        case let .intrinsic(maxWidth):
            let width = maxWidth ?? UIScreen.main.bounds.width
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        case let .fullContent(width, minimumHeight):
            let height = minimumHeight ?? 1
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        case let .fullContent2D(minimumSize):
            hostingController.view.frame = CGRect(origin: .zero, size: minimumSize)
    }

    return hostingController
}
