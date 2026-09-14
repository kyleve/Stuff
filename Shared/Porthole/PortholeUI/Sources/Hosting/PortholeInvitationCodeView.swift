import CoreGraphics
import SwiftUI

struct PortholeInvitationCodeView: View {
    let image: CGImage?
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().interpolation(.none)
                .scaledToFit().frame(maxWidth: stylesheet.hosting.invitationSize)
                .accessibilityLabel("One-time remote enrollment QR code")
        } else {
            Text("The QR code could not be generated. Copy the invitation text below.")
        }
    }
}
