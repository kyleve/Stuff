import SwiftUI
import Testing
import UIKit
import WhereTesting

private enum LifecycleEvent {
    case viewWillAppear
    case viewDidAppear
    case viewWillDisappear
    case viewDidDisappear
}

private final class LifecycleTrackingViewController: UIViewController {
    private(set) var events: [LifecycleEvent] = []

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        events.append(.viewWillAppear)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        events.append(.viewDidAppear)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        events.append(.viewWillDisappear)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        events.append(.viewDidDisappear)
    }
}

private struct OnAppearProbe: View {
    let mark: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear(perform: mark)
    }
}

@MainActor
struct ShowLifecycleTests {
    @Test func showRunsUIKitAppearanceLifecycle() throws {
        let tracked = LifecycleTrackingViewController()

        try show(tracked) { hosted in
            try waitFor { hosted.events.contains(.viewDidAppear) }
            #expect(hosted.events.contains(.viewWillAppear))
            #expect(hosted.parent != nil)
            #expect(hosted.view.window != nil)
        }

        try waitFor { tracked.events.contains(.viewWillDisappear) }
        tracked.view.layoutIfNeeded()

        #expect(tracked.parent == nil)
    }

    @Test func showRunsSwiftUIOnAppear() throws {
        var appeared = false
        let hosted = UIHostingController(rootView: OnAppearProbe { appeared = true })

        try show(hosted) { _ in
            try waitFor { appeared }
        }

        #expect(appeared)
    }
}
