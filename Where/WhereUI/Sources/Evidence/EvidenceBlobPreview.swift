import SwiftUI
import UIKit
import WhereCore

/// Renders an evidence attachment's bytes according to its
/// `EvidenceContentType`: PDFs in a `PDFView`, images inline, plain text in a
/// scroll view, and anything else (or bytes that fail to decode as their
/// declared type) as an honest "no preview" placeholder.
struct EvidenceBlobPreview: View {
    let data: Data
    let contentType: EvidenceContentType

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        // Exhaustive over `EvidenceContentType` (no `default`): a new content
        // type is a compile error here, not a silent fall-through to "raw".
        switch contentType {
            case .pdf:
                PDFDocumentView(data: data)
                    .frame(minHeight: stylesheet.evidence.pdfPreviewMinHeight)
                    .clipShape(RoundedRectangle(cornerRadius: stylesheet.evidence
                            .previewCornerRadius))
            case .image:
                imagePreview
            case .plainText:
                textPreview
            case .rawData, .other:
                unavailable
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: stylesheet.evidence.previewCornerRadius))
                .accessibilityLabel(String(localized: .primaryEvidence))
        } else {
            failedToDecode
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if let text = String(data: data, encoding: .utf8) {
            // No inner ScrollView: the detail view already scrolls, and nesting
            // a same-axis scroll view fights that gesture. Let the text flow in
            // the outer scroll instead.
            Text(text)
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            failedToDecode
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label(String(localized: .evidenceDetailNoPreviewTitle), systemImage: "doc.questionmark")
        } description: {
            Text(String(localized: .evidenceDetailNoPreviewDescription))
        }
    }

    private var failedToDecode: some View {
        ContentUnavailableView {
            Label(String(localized: .evidenceDetailNoPreviewTitle), systemImage: "doc.questionmark")
        } description: {
            Text(String(localized: .evidenceDetailPreviewFailed))
        }
    }
}

#if DEBUG
    #Preview("Plain text") {
        EvidenceBlobPreview(
            data: Data("SFO → JFK\nSeat 14C\nFebruary 3, 2026".utf8),
            contentType: .plainText,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
