import SwiftUI
import UIKit

/// One complete process runtime for Where.
///
/// `AppDelegate` selects one conformer before launch and delegates through this
/// existential for the rest of the process. The root is intentionally type
/// erased at this single, immutable boundary so the regular and Inspector view
/// types never require a mode switch in `WhereApp`.
@MainActor
protocol WhereApplicationRuntime: AnyObject {
    func didFinishLaunching(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?,
    ) -> Bool

    func makeRootView() -> AnyView
}
