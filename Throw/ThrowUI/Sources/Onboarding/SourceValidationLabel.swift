import SFSafeSymbols
import SwiftUI

struct SourceValidationLabel: View {
    let state: SourceValidationState

    var body: some View {
        switch state {
            case .untested:
                Label(
                    String(localized: .failureSourceNotValidated),
                    systemSymbol: .exclamationmarkTriangle,
                )
                .foregroundStyle(.secondary)
            case .testing:
                HStack {
                    ProgressView()
                    Text(.statusLoading)
                }
            case .succeeded:
                Label(String(localized: .statusHealthy), systemSymbol: .checkmarkCircleFill)
                    .foregroundStyle(.green)
            case let .failed(failure):
                Label(failure.localizedDescription, systemSymbol: .xmarkCircleFill)
                    .foregroundStyle(.red)
        }
    }
}
