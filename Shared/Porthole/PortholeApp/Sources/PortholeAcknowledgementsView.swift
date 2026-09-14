import CreditKit
import SwiftUI

/// The app ships its own report; library and development-tool credits remain distinct.
struct PortholeAcknowledgementsView: View {
    let report: Result<AttributionManifest, any Error>

    var body: some View {
        List {
            switch report {
                case let .success(manifest):
                    credits(manifest.credits(ofKind: .library), title: "Libraries")
                    credits(manifest.credits(ofKind: .developmentTool), title: "Development tools")
                case let .failure(error):
                    Section("Report unavailable") {
                        Text(error.localizedDescription)
                    }
            }
        }
        .navigationTitle("Acknowledgements")
    }

    private func credits(_ credits: [SoftwareCredit], title: String) -> some View {
        Section(title) {
            ForEach(credits) { credit in
                NavigationLink {
                    List {
                        Section {
                            LabeledContent("Version", value: credit.version)
                            LabeledContent("License", value: credit.license.name)
                            if let url = credit.homepageURL { Link(
                                "Project website",
                                destination: url,
                            ) }
                        }
                        Section("License notice") {
                            Text(credit.license.text).textSelection(.enabled)
                        }
                    }
                    .navigationTitle(credit.name)
                } label: { Text(credit.name) }
            }
        }
    }
}

#Preview {
    NavigationStack {
        PortholeAcknowledgementsView(report: .success(AttributionManifest(credits: [
            SoftwareCredit(
                name: "Example library",
                kind: .library,
                version: "1.0",
                homepageURL: URL(string: "https://example.com"),
                license: LicenseNotice(
                    name: "Example license",
                    text: "Example notice for this preview.",
                ),
            ),
        ])))
    }
}
