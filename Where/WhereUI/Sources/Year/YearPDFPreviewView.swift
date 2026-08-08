import SwiftUI

/// Paged in-app preview for a completed annual report. Sharing uses the typed
/// `YearPDFFile` representation, so Mail, Files, AirDrop, Messages, and other
/// installed destinations all receive the same finished PDF.
struct YearPDFPreviewView: View {
    private let source: PDFDocumentView.Source
    private let file: YearPDFFile?

    init(file: YearPDFFile) {
        source = .file(file.url)
        self.file = file
    }

    #if DEBUG
        init(previewData: Data) {
            source = .data(previewData)
            file = nil
        }
    #endif

    var body: some View {
        PDFDocumentView(source: source)
            .navigationTitle(String(localized: .exportReportPreviewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let file {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(
                            item: file,
                            preview: SharePreview(file.suggestedFilename),
                        ) {
                            Label(
                                String(localized: .exportReportShare),
                                systemImage: "square.and.arrow.up",
                            )
                        }
                    }
                }
            }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            YearPDFPreviewView(previewData: PDFDocumentView.previewData)
        }
    }
#endif
