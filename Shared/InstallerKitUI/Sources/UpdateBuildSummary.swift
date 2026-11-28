import InstallerKit
import SwiftUI

struct UpdateBuildSummary: View {
    let release: UpdateCatalog.Release
    var title: LocalizedStringResource?

    var body: some View {
        UpdateCard(title: title) {
            UpdateBuildMetrics(release: release)
        }
    }
}

private struct UpdateBuildMetrics: View {
    let release: UpdateCatalog.Release
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: stylesheet.summary.spacing) {
            UpdateBuildMetric(title: .installerVersion, value: release.buildDetails?.version)
            UpdateBuildMetric(
                title: .installerDownload,
                value: release.buildDetails?.sizeBytes.formatted(.byteCount(style: .file)),
            )
            UpdateBuildMetric(
                title: .installerRequiresOS,
                value: release.buildDetails.map { $0.minimumOSVersion + "+" },
            )
            UpdateBuildMetric(
                title: .installerPublished,
                value: release.publishedAt
                    .formatted(.dateTime.month(.abbreviated).day().year()),
            )
        }
    }

    private var columns: [GridItem] {
        switch stylesheet.summary.columns {
            case .adaptive: [GridItem(
                    .adaptive(minimum: stylesheet.summary.minimumColumnWidth),
                    spacing: stylesheet.summary.spacing,
                    alignment: .topLeading,
                )]
            case .single: [GridItem(.flexible(), alignment: .leading)]
        }
    }
}

private struct UpdateBuildMetric: View {
    let title: LocalizedStringResource
    let value: String?
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.summary.itemSpacing) {
            Text(title)
                .font(stylesheet.summary.labelFont)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(verbatim: value ?? String(localized: .installerNotRecorded))
                .font(stylesheet.summary.valueFont)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
