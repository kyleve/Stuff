import SwiftUI

/// Compact forward routes and inferred reverse cues for one screen.
struct FlyoverRouteSummary<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let catalog: FlyoverCatalog<ScreenID>

    var body: some View {
        let outgoing = catalog.transitions.filter { $0.source == screen.id }
        let incoming = catalog.transitions.filter { $0.destination == screen.id }

        HStack(spacing: 8) {
            ForEach(Array(outgoing.enumerated()), id: \.offset) { _, transition in
                Label(
                    transition.label ?? destinationTitle(for: transition),
                    systemImage: transition
                        .kind == .push ? "arrow.right" : "rectangle.portrait.on.rectangle.portrait",
                )
            }
            ForEach(Array(incoming.enumerated()), id: \.offset) { _, transition in
                Label(
                    transition.kind == .push ? "Back" : "Dismiss",
                    systemImage: transition.kind == .push ? "arrow.left" : "xmark",
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .frame(height: 34)
    }

    private func destinationTitle(
        for transition: FlyoverTransition<ScreenID>,
    ) -> String {
        catalog.screen(id: transition.destination)?.title ?? transition.kind.rawValue
    }
}
