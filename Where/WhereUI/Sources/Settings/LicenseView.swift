import CreditKit
import SwiftUI

/// The full license notice for one credited work, pushed from Settings > About.
/// Permissive licenses require the notice verbatim, so it is rendered as plain
/// monospaced text, unreflowed and untruncated.
struct LicenseView: View {
    let credit: SoftwareCredit

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxLarge) {
                header
                notice
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(credit.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(credit.licenseName)
                .font(.headline)
            Text(credit.version)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = credit.homepageURL {
                Link(url.absoluteString, destination: url)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let text = credit.licenseText() {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
        } else {
            // The bundled file is missing or unreadable — `licenseText()` has
            // already fault-logged it. Say so, rather than showing an empty page
            // that reads like a license with no terms.
            Text(String(localized: .settingsAboutLicenseUnavailable))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            if let credit = CreditCatalog.shared.credits.first {
                LicenseView(credit: credit)
            }
        }
        .whereBroadwayRoot()
    }
#endif
