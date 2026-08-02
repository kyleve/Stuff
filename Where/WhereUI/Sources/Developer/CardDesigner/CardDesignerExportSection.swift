#if DEBUG
    import SwiftUI

    struct CardDesignerExportSection: View {
        let configuration: CardDesignerConfiguration

        var body: some View {
            Section {
                ShareLink(
                    item: CardDesignerJSONExport(configuration: configuration),
                    preview: SharePreview(String(localized: .cardDesignerJSONExport)),
                ) {
                    Label(
                        String(localized: .cardDesignerJSONExport),
                        systemImage: "doc.badge.gearshape",
                    )
                }
                ShareLink(
                    item: CardDesignerSwiftExport(
                        source: CardDesignerSwiftExporter.source(for: configuration),
                    ),
                    preview: SharePreview(String(localized: .cardDesignerSwiftExport)),
                ) {
                    Label(
                        String(localized: .cardDesignerSwiftExport),
                        systemImage: "swift",
                    )
                }
            } header: {
                Text(String(localized: .cardDesignerExport))
            } footer: {
                Text(String(localized: .cardDesignerExportFooter))
            }
        }
    }
#endif
