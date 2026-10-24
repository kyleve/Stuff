import CreditKit
import SwiftUI

struct SoftwareCreditLink: View {
    let credit: SoftwareCredit

    var body: some View {
        NavigationLink(value: credit) {
            VStack(alignment: .leading) {
                Text(credit.name)
                Text(credit.version)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
