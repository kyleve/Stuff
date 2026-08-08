import PDFKit
import SwiftUI
import UIKit

/// Reusable paged `PDFView` bridge for both evidence bytes and completed files.
/// The source identity is cached so ordinary SwiftUI updates do not rebuild the
/// `PDFDocument` and reset the reader's current page or zoom.
struct PDFDocumentView: UIViewRepresentable {
    enum Source: Hashable {
        case data(Data)
        case file(URL)
    }

    let source: Source

    init(source: Source) {
        self.source = source
    }

    init(data: Data) {
        source = .data(data)
    }

    init(url: URL) {
        source = .file(url)
    }

    final class Coordinator {
        var source: Source?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: [
            UIPageViewController.OptionsKey.interPageSpacing: 12,
        ])
        view.document = document
        context.coordinator.source = source
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.source != source else { return }
        context.coordinator.source = source
        view.document = document
    }

    private var document: PDFDocument? {
        switch source {
            case let .data(data): PDFDocument(data: data)
            case let .file(url): PDFDocument(url: url)
        }
    }
}

#if DEBUG
    extension PDFDocumentView {
        static let previewData: Data = {
            let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
            return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                context.beginPage()
                let title = String(localized: .exportReportPreviewTitle) as NSString
                title.draw(
                    at: CGPoint(x: 48, y: 64),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)],
                )
            }
        }()
    }

    #Preview {
        PDFDocumentView(data: PDFDocumentView.previewData)
    }
#endif
