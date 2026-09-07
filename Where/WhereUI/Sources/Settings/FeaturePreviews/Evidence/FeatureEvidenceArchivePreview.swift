import SFSafeSymbols
import SwiftUI
import WhereCore

/// The settled archive result in the evidence walkthrough. Actual evidence is
/// limited to kind and date; attachment bytes and user notes remain undisclosed.
struct FeatureEvidenceArchivePreview: View {
    enum Content: Equatable {
        case loading
        case actual(Evidence)
        case example(Date)
        case failed(Date)
    }

    let content: Content

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                Label(
                    String(localized: .settingsExploreEvidenceArchiveTitle),
                    systemSymbol: .archivebox,
                )
                .font(.headline)

                switch content {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    case let .actual(evidence):
                        archiveRow(kind: evidence.kind, date: evidence.capturedAt)
                    case let .example(date), let .failed(date):
                        archiveRow(kind: .boardingPass, date: date)
                }

                if case .failed = content {
                    Label(
                        String(localized: .settingsExploreEvidenceFallback),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func archiveRow(kind: EvidenceKind, date: Date) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    archiveIcon(kind)
                    archiveText(kind: kind, date: date)
                }
            } else {
                HStack(spacing: stylesheet.spacing.medium) {
                    archiveIcon(kind)
                    archiveText(kind: kind, date: date)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func archiveIcon(_ kind: EvidenceKind) -> some View {
        Image(systemSymbol: kind.symbol)
            .font(.system(size: 22))
            .foregroundStyle(.indigo)
            .frame(width: 44, height: 44)
            .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func archiveText(kind: EvidenceKind, date: Date) -> some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(kind.displayName)
                .font(.headline)
            Text(date, format: .dateTime.month(.abbreviated).day().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
    #Preview {
        FeatureEvidenceArchivePreview(content: .example(PreviewSupport.referenceNow))
            .padding()
            .whereBroadwayRoot()
    }
#endif
