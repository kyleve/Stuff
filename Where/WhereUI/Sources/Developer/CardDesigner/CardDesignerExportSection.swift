import SFSafeSymbols
#if DEBUG
    import SwiftUI
    import UIKit

    struct CardDesignerExportSection: View {
        let configuration: CardDesignerConfiguration
        @State private var diffOnly = false
        @State private var copiedFormat: CopiedFormat?

        var body: some View {
            Section {
                Toggle(String(localized: .cardDesignerDiffOnly), isOn: $diffOnly)
                ShareLink(
                    item: CardDesignerJSONExport(
                        configuration: configuration,
                        diffOnly: diffOnly,
                    ),
                    preview: SharePreview(String(localized: .cardDesignerJsonExport)),
                ) {
                    Label(
                        String(localized: .cardDesignerShareJSON),
                        systemSymbol: .docBadgeGearshape,
                    )
                }
                Button(action: copyJSON) {
                    Label(
                        String(
                            localized: copiedFormat == .json
                                ? .cardDesignerCopiedJSON
                                : .cardDesignerCopyJSON,
                        ),
                        systemSymbol: copiedFormat == .json ? .checkmark : .documentOnDocument,
                    )
                }
                ShareLink(
                    item: CardDesignerSwiftExport(
                        source: CardDesignerSwiftExporter.source(
                            for: configuration,
                            diffOnly: diffOnly,
                        ),
                    ),
                    preview: SharePreview(String(localized: .cardDesignerSwiftExport)),
                ) {
                    Label(
                        String(localized: .cardDesignerShareSwift),
                        systemSymbol: .swift,
                    )
                }
                Button(action: copySwift) {
                    Label(
                        String(
                            localized: copiedFormat == .swift
                                ? .cardDesignerCopiedSwift
                                : .cardDesignerCopySwift,
                        ),
                        systemSymbol: copiedFormat == .swift ? .checkmark : .documentOnDocument,
                    )
                }
            } header: {
                Text(String(localized: .cardDesignerExport))
            } footer: {
                Text(String(localized: .cardDesignerExportFooter))
            }
            .sensoryFeedback(.success, trigger: copiedFormat)
            .onChange(of: diffOnly) { copiedFormat = nil }
            .onChange(of: configuration) { copiedFormat = nil }
        }

        private func copyJSON() {
            UIPasteboard.general.string = CardDesignerJSONExporter.text(
                for: configuration,
                diffOnly: diffOnly,
            )
            copiedFormat = .json
        }

        private func copySwift() {
            UIPasteboard.general.string = CardDesignerSwiftExporter.source(
                for: configuration,
                diffOnly: diffOnly,
            )
            copiedFormat = .swift
        }

        private enum CopiedFormat: Equatable {
            case json
            case swift
        }
    }

    #Preview {
        Form {
            CardDesignerExportSection(configuration: .standard)
        }
    }
#endif
