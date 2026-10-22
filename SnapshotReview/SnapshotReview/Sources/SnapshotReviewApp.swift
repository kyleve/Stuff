import SnapshotReviewCore
import SnapshotReviewUI
import SwiftUI

@main
struct SnapshotReviewApp: App {
    @State private var model = ReviewBrowserModel(
        storage: ReviewWorkspaceStore(),
        preferences: .standard,
    )
    var body: some Scene {
        WindowGroup {
            ReviewBrowserView(model: model)
        }
        .commands { ReviewCommands(model: model) }
    }
}
