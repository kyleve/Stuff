import SwiftUI

/// A labeled rule that groups overflow columns belonging to one route depth.
struct FlyoverDepthBandBackdrop: View {
    let band: FlyoverDepthBand
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.depthBand
        VStack(alignment: .leading, spacing: style.labelSpacing) {
            Text(title)
                .font(style.labelFont)
                .foregroundStyle(style.labelColor)
                .padding(.leading, style.labelLeadingPadding)

            Rectangle()
                .fill(style.ruleColor.opacity(style.ruleOpacity))
                .frame(height: style.ruleWidth)

            Spacer(minLength: 0)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(style.ruleColor.opacity(showsLeadingRule ? style.ruleOpacity : 0))
                .frame(width: style.ruleWidth)
        }
        .frame(width: band.frame.width, height: band.frame.height, alignment: .topLeading)
        .position(x: band.frame.midX, y: band.frame.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var title: String {
        switch band.kind {
            case .route(depth: 0):
                "Entry"
            case let .route(depth):
                "Depth \(depth)"
            case .unlinked:
                "Unlinked"
        }
    }

    private var accessibilityTitle: String {
        switch band.kind {
            case .route(depth: 0):
                "Entry route depth"
            case let .route(depth):
                "Route depth \(depth)"
            case .unlinked:
                "Unlinked screens"
        }
    }

    private var showsLeadingRule: Bool {
        band.kind != .route(depth: 0)
    }
}
