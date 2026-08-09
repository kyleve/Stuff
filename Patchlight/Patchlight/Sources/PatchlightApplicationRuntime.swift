import SwiftUI
import UIKit

/// One complete process runtime, selected once before launch.
@MainActor
protocol PatchlightApplicationRuntime: AnyObject {
    func didFinishLaunching(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool

    func makeRootView() -> AnyView
}
