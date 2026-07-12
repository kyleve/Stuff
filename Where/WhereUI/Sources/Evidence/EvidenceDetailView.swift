import SwiftUI
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
                header
                preview
            }
            .padding()
        }
        .navigationTitle(model.evidence.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.blobState == .idle { await model.load() }
        }
    }

    private var header: some View {
        let evidence = model.evidence
        return VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Label(evidence.kind.displayName, systemImage: evidence.kind.symbolName)
                .font(.title3.weight(.semibold))
            Text(evidence.capturedAt.formatted(date: .complete, time: .shortened))
                .foregroundStyle(.secondary)
            if let region = evidence.region {
                Label(region.localizedName, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            }
            if let note = evidence.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                    Text(.evidenceDetailNoteHeader)
                        .font(.subheadline.weight(.semibold))
                    Text(note)
                }
                .padding(.top, stylesheet.spacing.xSmall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var preview: some View {
        switch model.blobState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: stylesheet.evidence.loadingMinHeight)
            case let .loaded(data):
                if let data {
                    EvidenceBlobPreview(data: data, contentType: model.evidence.contentType)
                } else {
                    noAttachment
                }
            case let .failed(message):
                ContentUnavailableView {
                    Label(.evidenceFailedTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
        }
    }

    private var noAttachment: some View {
        ContentUnavailableView {
            Label(.evidenceDetailNoAttachment, systemImage: "doc")
        } description: {
            Text(.evidenceDetailNoPreviewDescription)
        }
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
