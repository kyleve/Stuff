import SwiftUI
import WhereCore

/// Home tab: the regions you spend the most days in. Filled out in a later
/// step.
struct PrimaryView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            Text("Primary")
                .navigationTitle("Where")
                .accessibilityIdentifier("where_root_title")
        }
    }
}
