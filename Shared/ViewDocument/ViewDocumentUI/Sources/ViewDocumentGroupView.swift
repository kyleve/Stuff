import SwiftUI
import ViewDocumentCore

struct ViewDocumentGroupView: View {
    let axis: ViewDocument.Axis
    let alignment: ViewAlignment
    let spacing: Double
    let children: [ViewDocument.Node]
    let assets: ViewDocumentAssets
    let appearance: ViewDocumentAppearance
    let policy: ViewDocumentView.Policy

    var body: some View {
        switch axis {
            case .horizontal:
                HStack(alignment: alignment.alignment.vertical, spacing: spacing) {
                    nodes
                }
            case .vertical:
                VStack(alignment: alignment.alignment.horizontal, spacing: spacing) {
                    nodes
                }
            case .overlay:
                ZStack(alignment: alignment.alignment) {
                    nodes
                }
        }
    }

    private var nodes: some View {
        ForEach(children) { node in
            ViewDocumentNodeView(node: node, assets: assets, appearance: appearance, policy: policy)
        }
    }
}
