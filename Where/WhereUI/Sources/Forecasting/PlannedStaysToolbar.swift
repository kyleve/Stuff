import SFSafeSymbols
import SwiftUI

/// Shared planning entry point; the host controls visibility and presentation.
struct PlannedStaysToolbar: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(
                String(localized: .plannedStaysTitle),
                systemSymbol: .calendarBadgeClock,
                action: action,
            )
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            Color.clear
                .toolbar { PlannedStaysToolbar {} }
        }
    }
#endif
