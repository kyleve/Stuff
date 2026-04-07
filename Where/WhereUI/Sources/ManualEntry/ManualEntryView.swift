import SwiftUI

struct ManualEntryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Manual Corrections Coming Next",
                systemImage: "square.and.pencil",
                description: Text("Use this area to add travel notes, adjust state attribution, and attach evidence."),
            )
            .navigationTitle("Manual")
            .accessibilityIdentifier("where_manual")
        }
    }
}
