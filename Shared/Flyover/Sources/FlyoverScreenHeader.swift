import SwiftUI

/// The title and focus action at the top of a Flyover overview card.
struct FlyoverScreenHeader<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        HStack {
            Text(screen.title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            Button("Inspect \(screen.title)", systemImage: "arrow.up.left.and.arrow.down.right") {
                model.focus(screen)
            }
            .labelStyle(.iconOnly)
        }
        .padding(12)
    }
}
