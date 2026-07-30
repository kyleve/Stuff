import SwiftUI

/// A labeled visual boundary around one Flyover group.
struct FlyoverGroupBackdrop: View {
    let title: String
    let frame: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(.background.opacity(0.75))
            .stroke(.quaternary, lineWidth: 2)
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.title2.bold())
                    .padding(20)
            }
            .position(x: frame.midX, y: frame.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) screen group")
    }
}
