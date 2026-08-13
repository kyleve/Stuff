import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A backup export presented as a composed private record rather than an inline
/// Settings spinner. The native share sheet is raised immediately when the
/// model publishes `.ready`; there is no artificial completion delay.
struct BackupPreparationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot
    @Environment(\.stylesheet) private var stylesheet
    @State private var presentedShareItem: BackupShareSheet.Item?
    @State private var completedExports = 0

    let backup: BackupModel
    private let injectedGeneratedDate: Date?

    init(backup: BackupModel, generatedDate: Date? = nil) {
        self.backup = backup
        injectedGeneratedDate = generatedDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                record
                    .padding(stylesheet.spacing.xxxLarge)
            }
            .background(stylesheet.palette.brand.canvas)
            .navigationTitle(String(localized: .settingsBackupPreparationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) { close() }
                }
            }
        }
        .sheet(item: $presentedShareItem) { item in
            BackupShareSheet(item: item)
        }
        .onChange(of: backup.exportState, initial: true) { _, state in
            guard case let .ready(url) = state else { return }
            guard !isCapturingSnapshot else { return }
            completedExports += 1
            presentedShareItem = BackupShareSheet.Item(url: url)
        }
        .sensoryFeedback(.success, trigger: completedExports)
        .onDisappear {
            if case .preparing = backup.exportState {
                backup.cancelExport()
            }
        }
    }

    private var closeTitle: String {
        if case .preparing = backup.exportState {
            return String(localized: .commonCancel)
        }
        return String(localized: .commonDone)
    }

    private var record: some View {
        let style = stylesheet.recordPreparation
        return VStack(alignment: .leading, spacing: style.sectionSpacing) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                        HStack(alignment: .top) {
                            preparationEyebrow
                            Spacer(minLength: stylesheet.spacing.medium)
                            preparationSeal
                        }
                        preparationTitle
                    }
                } else {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                            preparationEyebrow
                            preparationTitle
                        }
                        Spacer(minLength: stylesheet.spacing.large)
                        preparationSeal
                    }
                }
            }

            Divider()

            metadataRow(
                label: String(localized: .settingsBackupCoveredScope),
                value: String(localized: .settingsBackupCoveredScopeValue),
            )

            stateContent
        }
        .padding(style.padding)
        .background(stylesheet.palette.brand.raisedPaper)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .stroke(
                    stylesheet.palette.brand.brass.opacity(style.borderOpacity),
                    lineWidth: 0.75,
                )
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateContent: some View {
        let style = stylesheet.recordPreparation
        switch backup.exportState {
            case .idle:
                SystemActivityIndicator(tint: stylesheet.palette.brand.ink)
                    .frame(maxWidth: .infinity)
            case let .preparing(progress):
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(String(localized: .settingsBackupExporting))
                            .font(style.statusFont)
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(style.figureFont)
                            .monospacedDigit()
                    } else {
                        HStack {
                            Text(String(localized: .settingsBackupExporting))
                                .font(style.statusFont)
                            Spacer()
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(style.figureFont)
                                .monospacedDigit()
                        }
                    }
                    ProgressView(value: progress)
                        .tint(stylesheet.palette.brand.midnight)
                }
                .accessibilityElement(children: .combine)
            case let .ready(url):
                VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                    Label(
                        String(localized: .settingsBackupReady),
                        systemSymbol: .checkmarkSeal,
                    )
                    .font(style.statusFont)
                    .foregroundStyle(stylesheet.palette.brand.forest)
                    if let date = generatedDate(for: url) {
                        metadataRow(
                            label: String(localized: .settingsBackupGenerated),
                            value: date.formatted(date: .long, time: .shortened),
                        )
                    }
                }
            case let .failed(message):
                VStack(alignment: .leading, spacing: stylesheet.spacing.large) {
                    Label(
                        String(localized: .settingsBackupErrorTitle),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                    .font(style.statusFont)
                    .foregroundStyle(stylesheet.palette.brand.oxblood)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button(String(localized: .commonRetry)) {
                        backup.resetExport()
                        backup.prepareExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(stylesheet.palette.brand.midnight)
                }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        let style = stylesheet.recordPreparation
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                    Text(label)
                        .font(style.metadataLabelFont)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(style.metadataValueFont)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(style.metadataLabelFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(value)
                        .font(style.metadataValueFont)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var preparationEyebrow: some View {
        Text(String(localized: .settingsBackupPreparationEyebrow))
            .font(stylesheet.recordPreparation.eyebrowFont)
            .tracking(1.8)
            .foregroundStyle(stylesheet.palette.brand.brass)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var preparationTitle: some View {
        Text(String(localized: .settingsBackupDocumentTitle))
            .font(stylesheet.recordPreparation.titleFont)
            .foregroundStyle(stylesheet.palette.brand.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var preparationSeal: some View {
        WhereSeal(tint: stylesheet.palette.brand.brass)
            .frame(width: stylesheet.recordPreparation.sealSize)
            .accessibilityHidden(true)
    }

    private func generatedDate(for url: URL) -> Date? {
        if let injectedGeneratedDate { return injectedGeneratedDate }
        return try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private func close() {
        if case .preparing = backup.exportState {
            backup.cancelExport()
        } else {
            backup.resetExport()
        }
        dismiss()
    }
}

#if DEBUG
    extension BackupPreparationView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                snapshot(
                    name: "Preparing",
                    state: .preparing(progress: 0.46),
                    configurations: .fullContentScreenDefaults + [
                        SnapshotConfiguration(
                            layoutDirection: .rightToLeft,
                            device: .iPhoneFullContent,
                        ),
                    ],
                ),
                snapshot(
                    name: "Ready",
                    state: .ready(URL(fileURLWithPath: "/tmp/Where Private Record.zip")),
                    generatedDate: PreviewSupport.referenceNow,
                ),
                snapshot(name: "Failed", state: .failed(message: "iCloud is unavailable.")),
            ]
        }

        private static func snapshot(
            name: String,
            state: BackupModel.ExportState,
            generatedDate: Date? = nil,
            configurations: [SnapshotConfiguration] = .phoneLightDark,
        ) -> SnapshotCase {
            whereSnapshot(name: name, configurations: configurations) {
                let model = PreviewSupport.backupModel()
                model.previewExport(state)
                return BackupPreparationView(backup: model, generatedDate: generatedDate)
            }
        }
    }

    #Preview {
        BackupPreparationView.snapshotPreviews
    }
#endif
