import SwiftUI

/// Keeps the Locations index available beside its calendar. SwiftUI removes the toggle;
/// UIKit owns the split controller's independent swipe-to-hide interaction.
struct LocationsSplitInteraction: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.configureSplit()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            configureSplit()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            configureSplit()
        }

        func configureSplit() {
            guard let splitViewController, !splitViewController.isCollapsed else { return }
            if splitViewController.presentsWithGesture {
                splitViewController.presentsWithGesture = false
            }
            if splitViewController.displayModeButtonVisibility != .never {
                splitViewController.displayModeButtonVisibility = .never
            }
        }
    }
}
