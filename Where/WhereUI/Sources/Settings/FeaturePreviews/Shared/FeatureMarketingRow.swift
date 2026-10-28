import SwiftUI

extension View {
    /// Places a complete marketing panel as a clear Form row over the shared
    /// patterned background and joins the screen's reveal sequence.
    func featureMarketingRow(order: Int) -> some View {
        modifier(FeatureMarketingRowModifier(order: order))
    }
}

private struct FeatureMarketingRowModifier: ViewModifier {
    let order: Int

    @Environment(\.stylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet.featureDiscovery.marketingPanel
        content
            .listRowBackground(Color.clear)
            .listRowInsets(.init(
                top: style.rowVerticalInset,
                leading: 0,
                bottom: style.rowVerticalInset,
                trailing: 0,
            ))
            .listRowSeparator(.hidden)
            .staggeredReveal(order: order)
    }
}
