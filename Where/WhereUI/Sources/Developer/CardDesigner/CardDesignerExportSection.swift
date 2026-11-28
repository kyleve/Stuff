#if DEBUG
    import SFSafeSymbols
    import SwiftUI
    import UIKit

    struct CardDesignerExportSection: View {
        let configuration: CardDesignerConfiguration
        @State private var diffOnly = false
        @State private var copiedFormat: CopiedFormat?

        var body: some View {
            Section {
                Toggle(String(localized: .cardDesignerDiffOnly), isOn: $diffOnly)
                CardDesignerJSONShareLink(configuration: configuration, diffOnly: diffOnly)
                CardDesignerCopyButton(
                    copied: copiedFormat == .json,
                    copyTitle: .cardDesignerCopyJSON,
                    copiedTitle: .cardDesignerCopiedJSON,
                    action: copyJSON,
                )
                CardDesignerSwiftShareLink(configuration: configuration, diffOnly: diffOnly)
                CardDesignerCopyButton(
                    copied: copiedFormat == .swift,
                    copyTitle: .cardDesignerCopySwift,
                    copiedTitle: .cardDesignerCopiedSwift,
                    action: copySwift,
                )
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

    private struct CardDesignerJSONShareLink: View {
        let configuration: CardDesignerConfiguration
        let diffOnly: Bool

        var body: some View {
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
        }
    }

    private struct CardDesignerSwiftShareLink: View {
        let configuration: CardDesignerConfiguration
        let diffOnly: Bool

        var body: some View {
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
        }
    }

    private struct CardDesignerCopyButton: View {
        let copied: Bool
        let copyTitle: LocalizedStringResource
        let copiedTitle: LocalizedStringResource
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(
                    String(localized: copied ? copiedTitle : copyTitle),
                    systemSymbol: copied ? .checkmark : .documentOnDocument,
                )
            }
        }
    }
#endif
