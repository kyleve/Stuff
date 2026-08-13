#if DEBUG
    import SFSafeSymbols
    import SwiftUI

    /// A crash trigger that requires an explicit destructive confirmation.
    struct DeveloperCrashButton: View {
        let crash: DeveloperCrash

        @State private var isConfirming = false

        var body: some View {
            Button(action: confirm) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(crash.title, systemSymbol: .exclamationmarkTriangle)
                    Text(crash.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityInputLabels([crash.title])
            .confirmationDialog(
                String(localized: .developerCrashConfirmationTitle),
                isPresented: $isConfirming,
                titleVisibility: .visible,
            ) {
                Button(
                    String(localized: .developerCrashConfirmationAction),
                    role: .destructive,
                    action: trigger,
                )
                Button(String(localized: .commonCancel), role: .cancel) {}
            } message: {
                Text(crash.detail)
            }
        }

        private func confirm() {
            isConfirming = true
        }

        private func trigger() {
            crash.trigger()
        }
    }

    #Preview {
        List {
            DeveloperCrashButton(crash: .swiftFatalError)
        }
        .whereBroadwayRoot()
    }
#endif
