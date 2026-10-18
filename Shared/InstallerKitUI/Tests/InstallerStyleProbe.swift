@testable import InstallerKitUI
import SwiftUI

@MainActor
final class InstallerStyleProbeBox {
    var style: InstallerStylesheet?
}

struct InstallerStyleProbe: ViewModifier {
    let box: InstallerStyleProbeBox
    @Environment(\.installerStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        content.onChange(of: stylesheet, initial: true) { _, value in box.style = value }
    }
}
