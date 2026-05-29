import SwiftUI
import WhereCore

/// Elsewhere tab: everywhere outside your primary regions. Filled out in a
/// later step.
struct SecondaryView: View {
    @Environment(WhereModel.self) private var model

    var body: some View {
        NavigationStack {
            Text("Elsewhere")
                .navigationTitle("Elsewhere")
        }
    }
}
