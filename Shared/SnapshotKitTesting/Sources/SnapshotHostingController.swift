import SnapshotKit
import SwiftUI
import UIKit

/// Builds a hosting controller for `view` with the configuration's appearance
/// traits applied and a starting frame set. Dynamic Type, color scheme, layout
/// direction, and legibility weight are applied through the SwiftUI environment
/// (so measurement reflects them) and mirrored onto UIKit trait overrides (for
/// any embedded UIKit); increased contrast — which SwiftUI can't set — is a
/// trait override only. Intrinsic components get only their width here; the
/// pipeline measures their height after the content settles.
///
/// SwiftUI transaction animations are disabled at the root: every state change
/// in the hosted tree commits its end state instantly instead of animating, so
/// finite time-based reveals no longer "run to completion" during settle — there
/// is no mid-flight frame to catch. The settle loop remains for `.task`-driven
/// async content, which still needs real suspension time to load.
@MainActor
func makeHostingController(
    for view: some View,
    configuration: SnapshotConfiguration,
    hostWidth: CGFloat,
) -> UIViewController {
    let styled = view
        .environment(\.colorScheme, configuration.colorScheme)
        .dynamicTypeSize(configuration.dynamicType)
        .environment(\.layoutDirection, configuration.layoutDirection)
        .environment(\.legibilityWeight, configuration.legibilityWeight)
        .snapshotLayoutTraits(configuration)
        .transaction {
            $0.disablesAnimations = true
            $0.animation = nil
        }
    let hostingController = UIHostingController(rootView: styled)
    hostingController.view.backgroundColor = .clear

    configuration.applyTraits(to: hostingController)

    switch configuration.device.size {
        case let .fixed(size):
            hostingController.view.frame = CGRect(origin: .zero, size: size)
        case let .intrinsic(maxWidth):
            let width = maxWidth ?? hostWidth
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        case let .fullContent(width, minimumHeight):
            let height = minimumHeight ?? 1
            hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        case let .fullContent2D(minimumSize):
            hostingController.view.frame = CGRect(origin: .zero, size: minimumSize)
    }

    return hostingController
}
