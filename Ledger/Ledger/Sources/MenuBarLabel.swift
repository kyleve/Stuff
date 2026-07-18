import LedgerCore
import SwiftUI

/// The SwiftUI content hosted in the status item: the `$` glyph and the
/// current-cycle amount, with the numeric-text content transition so digit
/// changes roll over like the popover's figure. Bound to the observable
/// session, it re-renders itself when the amount changes — no manual title
/// updates needed.
///
/// A hosted view doesn't auto-size a variable-length `NSStatusItem`, so the
/// label reports its rendered width via `onWidthChange`; the app delegate sets
/// the item's length to match (otherwise the amount is clipped to the icon).
struct MenuBarLabel: View {
    let session: LedgerSession
    let onWidthChange: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "dollarsign.circle")
            Text(session.statusTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 13))
        .padding(.horizontal, 4)
        .fixedSize()
        .animation(.default, value: session.statusTitle)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidthChange($0) }
    }
}
