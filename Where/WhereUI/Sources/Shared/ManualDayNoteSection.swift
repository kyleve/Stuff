import SwiftUI

struct ManualDayNoteSection: View {
    @Binding var note: String
    let isWriting: Bool

    var body: some View {
        Section {
            TextField(
                String(localized: .manualNotePlaceholder),
                text: $note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
            .disabled(isWriting)
        } header: {
            Text(String(localized: .manualNoteHeader))
        } footer: {
            Text(String(localized: .manualNoteFooter))
        }
    }
}

#if DEBUG
    #Preview("Manual entry") {
        ManualDayView.snapshotPreviews
    }
#endif
