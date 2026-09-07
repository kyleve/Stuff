import CreditKit
import SwiftUI

struct SoftwareCreditDetailView: View {
    let credit: SoftwareCredit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(credit.license.name)
                    .font(.headline)
                Text(credit.license.text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                if let homepageURL = credit.homepageURL {
                    Link(String(localized: .aboutProjectHomepage), destination: homepageURL)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
