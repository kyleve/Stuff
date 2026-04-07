import SwiftUI

struct ReportActionRow: View {
    let title: String
    let statusText: String?
    let onExport: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title) {
                HStack(spacing: 12) {
                    Button("Save", action: onExport)
                    Button("Share", action: onShare)
                }
                .buttonStyle(.borderless)
            }

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
