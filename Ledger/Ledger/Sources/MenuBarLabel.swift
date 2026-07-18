import LedgerCore
import SwiftUI

/// The SwiftUI content hosted in the status item: the `$` glyph and the
/// current-cycle amount, with the numeric-text content transition so digit
/// changes roll over like the popover's figure. Bound to the observable
/// session, it re-renders itself when the amount changes — no manual title
/// updates needed.
struct MenuBarLabel: View {
    let session: LedgerSession

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "dollarsign.circle")
            Text(session.statusTitle)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 13))
        .padding(.horizontal, 4)
        .animation(.default, value: session.statusTitle)
    }
}
