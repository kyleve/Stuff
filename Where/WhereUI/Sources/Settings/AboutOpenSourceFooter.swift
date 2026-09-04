import Foundation
import SwiftUI

/// A compact passport-style sign-off linking the About screen to Where's source.
struct AboutOpenSourceFooter: View {
    static let projectURL = URL(string: "https://github.com/kyleve/Stuff")!

    @Environment(\.stylesheet) private var stylesheet
    var body: some View {
        Link(destination: Self.projectURL) {
            StampBanner(
                systemSymbol: .chevronLeftForwardslashChevronRight,
                style: stylesheet.openSourceStamp,
                showsAccessory: true,
            ) {
                AboutOpenSourceStampText()
            }
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
                .listRowInsets(EdgeInsets())
        }
        .whereBroadwayRoot()
    }
#endif
