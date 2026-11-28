import PDFKit
import PeriscopeCore
import SFSafeSymbols
import SwiftUI
import UIKit
import WhereCore

/// Detail for one piece of evidence: its metadata (kind, capture date, region,
/// note) above a preview of the attachment bytes, which are loaded lazily via
/// `EvidenceDetailModel` (they live separately from the metadata). Pushed from
/// the evidence list.
struct EvidenceDetailView: View {
    @Environment(\.stylesheet) private var stylesheet
    @State private var model: EvidenceDetailModel

    init(evidence: Evidence, report: YearReportModel) {
        _model = State(initialValue: EvidenceDetailModel(
            evidence: evidence,
            services: report.services,
        ))
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen blob state.
        init(model: EvidenceDetailModel) {
            _model = State(initialValue: model)
        }
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
                EvidenceDetailHeader(evidence: model.evidence)
                EvidenceAttachmentPreview(
                    state: model.blobState,
                    contentType: model.evidence.contentType,
                )
            }
            .padding()
        }
        .navigationTitle(model.evidence.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.blobState == .idle {
                await model.load()
            }
        }
        // Log View Mode: reveal an inspect badge for this screen's
        // evidence-detail events (blob-load failures). A no-op in release.
        .debugLogInspectable(WhereLog.evidence(EvidenceDetailModelLog.self))
    }
}

private struct EvidenceDetailHeader: View {
    let evidence: Evidence
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Label(evidence.kind.displayName, systemSymbol: evidence.kind.symbol)
                .font(.title3.weight(.semibold))
            Text(evidence.capturedAt.formatted(date: .complete, time: .shortened))
                .foregroundStyle(.secondary)
            if let region = evidence.region {
                Label(region.localizedName, systemSymbol: .mappinAndEllipse)
                    .foregroundStyle(.secondary)
            }
            if let note = evidence.note, !note.isEmpty {
                EvidenceHeaderNote(note: note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EvidenceHeaderNote: View {
    let note: String
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Text(String(localized: .evidenceDetailNoteHeader))
                .font(.subheadline.weight(.semibold))
            Text(note)
        }
        .padding(.top, stylesheet.spacing.xSmall)
    }
}

private struct EvidenceAttachmentPreview: View {
    let state: EvidenceDetailModel.BlobState
    let contentType: EvidenceContentType
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        switch state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: stylesheet.evidence.loadingMinHeight)
            case let .loaded(data):
                if let data {
                    EvidenceBlobPreview(data: data, contentType: contentType)
                } else {
                    EvidenceWithoutAttachment()
                }
            case let .failed(message):
                EvidenceLoadFailure(message: message)
        }
    }
}

private struct EvidenceWithoutAttachment: View {
    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .evidenceDetailNoAttachment), systemSymbol: .doc)
        } description: {
            Text(String(localized: .evidenceDetailNoPreviewDescription))
        }
    }
}

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
                EvidenceImagePreview(data: data)
            case .plainText:
                EvidenceTextPreview(data: data)
            case .rawData, .other:
                UnavailableEvidencePreview(
                    description: String(localized: .evidenceDetailNoPreviewDescription),
                )
        }
    }
}

private struct EvidenceImagePreview: View {
    let data: Data
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: stylesheet.evidence.previewCornerRadius))
                .accessibilityLabel(String(localized: .primaryEvidence))
        } else {
            UnavailableEvidencePreview(description: String(localized: .evidenceDetailPreviewFailed))
        }
    }
}

private struct EvidenceTextPreview: View {
    let data: Data

    var body: some View {
        if let text = String(data: data, encoding: .utf8) {
            // No inner ScrollView: the detail view already scrolls, and nesting
            // a same-axis scroll view fights that gesture. Let the text flow in
            // the outer scroll instead.
            Text(text)
                .font(.callout.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            UnavailableEvidencePreview(description: String(localized: .evidenceDetailPreviewFailed))
        }
    }
}

private struct UnavailableEvidencePreview: View {
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .evidenceDetailNoPreviewTitle), systemSymbol: .docQuestionmark)
        } description: {
            Text(description)
        }
    }
}

/// Thin `PDFView` wrapper so evidence PDFs preview inline (auto-scaled, paged).
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    /// Remembers the bytes the current `PDFDocument` was built from, so
    /// `updateUIView` rebuilds only on a genuine change. Comparing against
    /// `PDFView.document?.dataRepresentation()` doesn't work: PDFKit re-encodes
    /// on export, so its byte count differs from the input and the document
    /// would be rebuilt on every layout pass — resetting the user's scroll/zoom.
    final class Coordinator {
        var data: Data?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        context.coordinator.data = data
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        view.document = PDFDocument(data: data)
    }
}

#if DEBUG
    #Preview("Text") {
        NavigationStack {
            EvidenceDetailView(
                model: PreviewSupport.evidenceDetailModel(
                    kind: .email,
                    contentType: .plainText,
                    blob: Data("Confirmation: your flight SFO→JFK departs 8:15 AM.".utf8),
                ),
            )
        }
    }

    #Preview("No attachment") {
        NavigationStack {
            EvidenceDetailView(
                model: PreviewSupport.evidenceDetailModel(
                    kind: .document,
                    contentType: .other(nil),
                    blob: nil,
                ),
            )
        }
    }
#endif

#if DEBUG
    extension EvidenceDetailView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            EvidenceDetailView.self,
            title: "Evidence Detail",
        ) { _ in
            EvidenceDetailView(model: PreviewSupport.evidenceDetailModel(
                kind: .planeTicket,
                contentType: .plainText,
                blob: Data("SFO → JFK · 14C".utf8),
            ))
        }
    }
#endif

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
