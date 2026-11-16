import SwiftUI

/// Optional shorthand for screens whose body is one ordinary vertical scroller.
protocol WhereScreen: View {
    associatedtype ScreenContent: View
    @ViewBuilder var content: ScreenContent { get }
    var contentWidth: WhereContentWidth? { get }
    var contentPadding: WhereContentPadding { get }
}

extension WhereScreen {
    var contentWidth: WhereContentWidth? {
        nil
    }

    var contentPadding: WhereContentPadding {
        .standard
    }

    var body: some View {
        content.whereScreenRoot(contentWidth, padding: contentPadding)
    }
}
