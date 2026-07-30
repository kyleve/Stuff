import SwiftUI

/// A labeled visual boundary around one Flyover group.
struct FlyoverGroupBackdrop: View {
    let title: String
    let frame: CGRect
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.group
        RoundedRectangle(cornerRadius: style.cornerRadius)
            .fill(style.fill.opacity(style.fillOpacity))
            .stroke(.quaternary, lineWidth: style.strokeWidth)
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(style.titleFont)
                    .padding(style.titlePadding)
            }
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) screen group")
    }
}
