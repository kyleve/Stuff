import Foundation
import SwiftUI

/// A compact passport-style sign-off linking the About screen to Where's source.
struct AboutOpenSourceFooter: View {
    static let projectURL = URL(string: "https://github.com/kyleve/Stuff")!

    var body: some View {
        Link(destination: Self.projectURL) {
            PassportCard(
                title: .settingsAboutSourceTitle,
                detail: .settingsAboutSourceAction,
                sealSystemImage: "chevron.left.forwardslash.chevron.right",
                accessorySystemImage: "arrow.up.right",
                isInteractive: true,
                tilt: nil,
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        Form {
            AboutOpenSourceFooter()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .whereBroadwayRoot()
    }
#endif
