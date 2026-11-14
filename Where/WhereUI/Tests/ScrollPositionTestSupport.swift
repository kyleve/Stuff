import BroadwayUI
import SwiftUI

/// Reads the production restoration entry without creating a second scroll view.
@MainActor
final class ScrollPositionCapture {
    var binding: Binding<ScrollPosition>?
}

struct ScrollPositionProbe<ID: Hashable & Sendable, Context: Hashable>: View {
    let capture: ScrollPositionCapture
    @BScrollPosition<ID, Context> private var position: ScrollPosition

    init(
        _ view: (some View).Type,
        role: some Hashable,
        context: Context,
        idType: ID.Type,
        capture: ScrollPositionCapture,
    ) {
        self.capture = capture
        _position = BScrollPosition(view, role: role, context: context, idType: idType)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { capture.binding = $position }
    }
}
