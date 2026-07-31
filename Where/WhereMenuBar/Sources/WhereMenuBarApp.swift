import SwiftUI

@main
struct WhereMenuBarApp: App {
    @NSApplicationDelegateAdaptor(WhereMenuBarAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
