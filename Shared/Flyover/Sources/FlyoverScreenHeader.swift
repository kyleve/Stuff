import SwiftUI

/// The title and focus action at the top of a Flyover overview card.
struct FlyoverScreenHeader<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        HStack {
            Text(screen.title)
                .font(stylesheet.screen.header.font)
                .lineLimit(1)
            Spacer()
            Button("Inspect \(screen.title)", systemImage: "arrow.up.left.and.arrow.down.right") {
                model.focus(screen)
            }
            .labelStyle(.iconOnly)
        }
        .padding(stylesheet.screen.header.padding)
    }
}
