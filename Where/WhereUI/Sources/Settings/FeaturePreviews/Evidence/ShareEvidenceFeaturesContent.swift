import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Keeps the gallery Form out of the enclosing focus and reveal scopes.
struct ShareEvidenceFeaturesContent: View {
    let report: YearReportModel
    let presentation: FeatureDiscoveryPresentation
    let archiveContent: FeatureEvidenceArchivePreview.Content

    var body: some View {
        Form {
            EvidenceGalleryHeader()

            Section {
                FeatureShareSheetPreview()
                    .featureMarketingRow(order: 1)
                    .settingsRow(
                        ShareEvidenceFeaturesView.Item.shareSheet,
                        restingBackground: .clear,
                    )
                FeatureEvidenceComposePreview(date: presentation.lockScreenDate)
                    .featureMarketingRow(order: 2)
                    .settingsRow(ShareEvidenceFeaturesView.Item.compose, restingBackground: .clear)
                FeatureEvidenceArchivePreview(content: archiveContent)
                    .featureMarketingRow(order: 3)
                    .settingsRow(ShareEvidenceFeaturesView.Item.archive, restingBackground: .clear)
                ArchiveLink()
            } footer: {
                EvidenceGalleryFooter()
            }
        }
        .whereFormRoot()
        .scrollContentBackground(.hidden)
        .background(FeatureDiscoveryBackground())
        .navigationDestination(for: Route.self) { route in
            switch route {
                case .archive: EvidenceListView(report: report)
            }
        }
    }

    private struct ArchiveLink: View {
        var body: some View {
            FeatureMarketingPanel {
                NavigationLink(value: Route.archive) {
                    Label {
                        Text(String(localized: .settingsExploreEvidenceOpenArchive))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemSymbol: .paperclip)
                            .foregroundStyle(SettingsDestination.shareEvidence
                                .iconColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .featureMarketingRow(order: 4)
        }
    }

    private enum Route: Hashable {
        case archive
    }
}

private struct EvidenceGalleryFooter: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(String(localized: .settingsExploreEvidenceFooter))
            FeatureDiscoveryDataFooter()
        }
        .staggeredReveal(order: 5)
    }
}

private struct EvidenceGalleryHeader: View {
    var body: some View {
        FeatureMarketingHeader(
            title: String(localized: .settingsExploreEvidenceTitle),
            tagline: String(localized: .settingsExploreEvidenceTagline),
            systemSymbol: SettingsDestination.shareEvidence.systemSymbol,
            tint: SettingsDestination.shareEvidence.iconColor,
        )
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .staggeredReveal(order: 0)
    }
}

#if DEBUG
    #Preview {
        NavigationStack { ShareEvidenceFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

/// A miniature system Share sheet that makes Where's extension visible inside
/// the app without pretending the gallery can launch a share with no source.
private struct FeatureShareSheetPreview: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                EvidencePreviewHeading(
                    title: .settingsExploreEvidenceShareTitle,
                    symbol: .squareAndArrowUp,
                )

                FeatureShareSourceList()

                Divider()

                EvidenceShareActionPreview()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EvidenceShareActionPreview: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(String(localized: .settingsExploreEvidenceShareAction))
                    .font(.headline)
                Text(String(localized: .settingsExploreEvidenceShareActionSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            AppIconImage(name: "AppIconClassic", size: 44)
        }
        .padding(.horizontal, stylesheet.spacing.small)
    }
}

#if DEBUG
    #Preview("Share Sheet") {
        FeatureShareSheetPreview()
            .padding()
            .whereBroadwayRoot()
    }
#endif

/// A read-only miniature of the compose form the Share extension presents.
private struct FeatureEvidenceComposePreview: View {
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                EvidencePreviewHeading(
                    title: .settingsExploreEvidenceComposeTitle,
                    symbol: .checkmarkCircle,
                )

                EvidenceComposeKind()
                Divider()
                EvidenceComposeDate(date: date)
                Divider()
                EvidenceAttachmentReady()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct EvidenceComposeKind: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(String(localized: .evidenceFormKind))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(
                EvidenceKind.boardingPass.displayName,
                systemSymbol: EvidenceKind.boardingPass.symbol,
            )
        }
    }
}

private struct EvidenceComposeDate: View {
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(String(localized: .evidenceFormDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.month(.abbreviated).day().year())
        }
    }
}

private struct EvidenceAttachmentReady: View {
    var body: some View {
        Label(
            String(localized: .settingsExploreEvidenceAttachmentReady),
            systemSymbol: .paperclip,
        )
        .foregroundStyle(.secondary)
    }
}

#if DEBUG
    #Preview("Compose") {
        FeatureEvidenceComposePreview(date: PreviewSupport.referenceNow)
            .padding()
            .whereBroadwayRoot()
    }
#endif

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

    var body: some View {
        let panelStyle = stylesheet.featureDiscovery.marketingPanel
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: panelStyle.contentSpacing) {
                EvidencePreviewHeading(
                    title: .settingsExploreEvidenceArchiveTitle,
                    symbol: .archivebox,
                )

                EvidenceArchiveResult(content: content)

                if case .failed = content {
                    EvidenceArchiveFallback()
                }
            }
        }
    }
}

private struct EvidenceArchiveRow: View {
    let kind: EvidenceKind
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Group {
            if stylesheet.featureDiscovery.evidenceArchive.layout == .stacked {
                VStack(
                    alignment: .leading,
                    spacing: stylesheet.featureDiscovery.evidenceArchive.spacing,
                ) {
                    EvidenceArchiveIcon(kind: kind)
                    EvidenceArchiveDescription(kind: kind, date: date)
                }
            } else {
                HStack(spacing: stylesheet.featureDiscovery.evidenceArchive.spacing) {
                    EvidenceArchiveIcon(kind: kind)
                    EvidenceArchiveDescription(kind: kind, date: date)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EvidenceArchiveIcon: View {
    let kind: EvidenceKind

    var body: some View {
        Image(systemSymbol: kind.symbol)
            .font(.system(size: 22))
            .foregroundStyle(.indigo)
            .frame(width: 44, height: 44)
            .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct EvidenceArchiveDescription: View {
    let kind: EvidenceKind
    let date: Date

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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

private struct EvidenceArchiveFallback: View {
    var body: some View {
        Label(
            String(localized: .settingsExploreEvidenceFallback),
            systemSymbol: .exclamationmarkIcloud,
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct EvidenceArchiveResult: View {
    let content: FeatureEvidenceArchivePreview.Content

    var body: some View {
        switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case let .actual(evidence):
                EvidenceArchiveRow(kind: evidence.kind, date: evidence.capturedAt)
            case let .example(date), let .failed(date):
                EvidenceArchiveRow(kind: .boardingPass, date: date)
        }
    }
}

#if DEBUG
    #Preview("Archive") {
        FeatureEvidenceArchivePreview(content: .example(PreviewSupport.referenceNow))
            .padding()
            .whereBroadwayRoot()
    }
#endif

private struct EvidencePreviewHeading: View {
    let title: LocalizedStringResource
    let symbol: SFSymbol

    var body: some View {
        Label(String(localized: title), systemSymbol: symbol)
            .font(.headline)
    }
}
