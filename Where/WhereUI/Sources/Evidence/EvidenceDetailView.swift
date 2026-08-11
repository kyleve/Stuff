import PeriscopeCore
import SFSafeSymbols
import SnapshotKit
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
        .background(stylesheet.palette.brand.canvas)
        .navigationTitle(model.evidence.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.blobState == .idle { await model.load() }
        }
        // Log View Mode: reveal an inspect badge for this screen's
        // evidence-detail events (blob-load failures). A no-op in release.
        .debugLogInspectable(WhereLog.evidence(EvidenceDetailModelLog.self))
    }

    private var header: some View {
        let evidence = model.evidence
        let archive = stylesheet.evidence.archive
        return VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    Text(String(localized: .evidenceDetailRecordLabel))
                        .font(archive.eyebrowFont)
                        .tracking(1.6)
                        .foregroundStyle(stylesheet.palette.brand.brass)
                    Text(evidence.kind.displayName)
                        .font(archive.titleFont)
                        .foregroundStyle(stylesheet.palette.brand.ink)
                }
                Spacer(minLength: stylesheet.spacing.large)
                WhereSeal(tint: stylesheet.palette.brand.brass)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemSymbol: evidence.kind.symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(stylesheet.palette.brand.ink)
                            .frame(width: 22, height: 22)
                            .background(stylesheet.palette.brand.raisedPaper, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(
                                        stylesheet.palette.brand.brass.opacity(0.45),
                                        lineWidth: 0.75,
                                    )
                            }
                    }
                    .frame(width: archive.headerSealSize)
                    .accessibilityHidden(true)
            }

            Divider()

            metadataRow(
                label: String(localized: .evidenceDetailCaptured),
                value: evidence.capturedAt.formatted(date: .complete, time: .shortened),
            )
            if let region = evidence.region {
                metadataRow(
                    label: String(localized: .evidenceDetailRegion),
                    value: region.localizedName,
                )
            }
            if let note = evidence.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                    Text(String(localized: .evidenceDetailNoteHeader))
                        .font(.subheadline.weight(.semibold))
                    Text(note)
                }
            }
        }
        .padding(archive.padding)
        .background(stylesheet.palette.brand.raisedPaper)
        .clipShape(RoundedRectangle(cornerRadius: archive.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: archive.cornerRadius)
                .stroke(
                    stylesheet.palette.brand.brass.opacity(archive.borderOpacity),
                    lineWidth: 0.75,
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func metadataRow(label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch model.blobState {
            case .idle, .loading:
                SystemActivityIndicator(tint: stylesheet.palette.brand.ink)
                    .frame(maxWidth: .infinity, minHeight: stylesheet.evidence.loadingMinHeight)
            case let .loaded(data):
                if let data {
                    EvidenceBlobPreview(data: data, contentType: model.evidence.contentType)
                } else {
                    noAttachment
                }
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        String(localized: .evidenceFailedTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(message)
                }
        }
    }

    private var noAttachment: some View {
        ContentUnavailableView {
            Label(String(localized: .evidenceDetailNoAttachment), systemSymbol: .doc)
        } description: {
            Text(String(localized: .evidenceDetailNoPreviewDescription))
        }
    }
}

#if DEBUG
    extension EvidenceDetailView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(
                    name: "TextAttachment",
                    configurations: .fullContentScreenDefaults + [
                        SnapshotConfiguration(
                            layoutDirection: .rightToLeft,
                            device: .iPhoneFullContent,
                        ),
                    ],
                    settle: .immediate,
                ) {
                    NavigationStack {
                        EvidenceDetailView(model: PreviewSupport.evidenceDetailModel(
                            kind: .email,
                            contentType: .plainText,
                            blob: Data("Confirmation: your flight SFO→JFK departs 8:15 AM.".utf8),
                        ))
                    }
                },
                whereSnapshot(name: "NoAttachment", configurations: .phoneLightDark) {
                    NavigationStack {
                        EvidenceDetailView(model: PreviewSupport.evidenceDetailModel(
                            kind: .document,
                            contentType: .other(nil),
                            blob: nil,
                        ))
                    }
                },
            ]
        }
    }
#endif

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
