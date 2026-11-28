import SFSafeSymbols
import SwiftUI

struct InspectorDeleteButton: View {
    let title: LocalizedStringKey
    let symbol: SFSymbol
    let question: LocalizedStringKey
    var confirmation: LocalizedStringKey?
    var message: LocalizedStringKey?
    var isDisabled = false
    @Binding var isConfirming: Bool
    let confirm: () -> Void

    var body: some View {
        Button(title, systemSymbol: symbol, role: .destructive) { isConfirming = true }
            .disabled(isDisabled)
            .confirmationDialog(question, isPresented: $isConfirming, titleVisibility: .visible) {
                Button(confirmation ?? title, role: .destructive, action: confirm)
            } message: {
                if let message {
                    Text(message)
                }
            }
    }
}

#if DEBUG
    #Preview { InspectorPreviewData.tablePreview() }
#endif
