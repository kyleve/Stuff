import PDFKit
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

    var body: some View {
        // Exhaustive over `EvidenceContentType` (no `default`): a new content
        // type is a compile error here, not a silent fall-through to "raw".
        switch contentType {
            case .pdf:
                PDFDocumentView(data: data)
                    .frame(minHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.compactCard))
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
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.compactCard))
                .accessibilityLabel(Strings.primaryEvidence)
        } else {
            failedToDecode
        }
    }

    @ViewBuilder
    private var textPreview: some View {
        if let text = String(data: data, encoding: .utf8) {
            ScrollView {
                Text(text)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 240)
        } else {
            failedToDecode
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label(Strings.evidenceNoPreviewTitle, systemImage: "doc.questionmark")
        } description: {
            Text(Strings.evidenceNoPreviewDescription)
        }
    }

    private var failedToDecode: some View {
        ContentUnavailableView {
            Label(Strings.evidenceNoPreviewTitle, systemImage: "doc.questionmark")
        } description: {
            Text(Strings.evidencePreviewFailed)
        }
    }
}

/// Thin `PDFView` wrapper so evidence PDFs preview inline (auto-scaled, paged).
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context _: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context _: Context) {
        // Only rebuild the document when the bytes actually change (cheap
        // identity check on length is enough for a single immutable blob).
        if view.document?.dataRepresentation()?.count != data.count {
            view.document = PDFDocument(data: data)
        }
    }
}
