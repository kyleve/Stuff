import SwiftUI

/// A full-screen, live inspector for one registered screen.
struct FlyoverFocusedView<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                FlyoverScreenContent(
                    screen: screen,
                    model: model,
                    isOverview: false,
                )
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FlyoverFocusedControls(screen: screen, model: model)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
