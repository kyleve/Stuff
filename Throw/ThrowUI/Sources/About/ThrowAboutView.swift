import CreditKit
import SFSafeSymbols
import SwiftUI

struct ThrowAboutView: View {
    let session: ThrowSession

    var body: some View {
        let credits = SoftwareCreditsPresentation(credits: session.softwareCredits)
        List {
            Section {
                Text(.aboutDisclaimer)
                Text(.aboutPersonalUse)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: .aboutAircraftData)) {
                if let adsbLolURL = URL(string: "https://www.adsb.lol/") {
                    Link(String(localized: .aboutAdsbLol), destination: adsbLolURL)
                }
                if let adsbLolPrivacyURL = URL(string: "https://www.adsb.lol/privacy-license/") {
                    Link(
                        String(localized: .aboutAdsbLolPrivacyLicense),
                        destination: adsbLolPrivacyURL,
                    )
                }
                if let readsbURL = URL(string: "https://github.com/wiedehopf/readsb") {
                    Link(String(localized: .aboutLocalReceiver), destination: readsbURL)
                }
                if let adsbExchangeURL =
                    URL(string: "https://www.adsbexchange.com/community/developer-hub/")
                {
                    Link(String(localized: .aboutAdsbExchange), destination: adsbExchangeURL)
                }
                if let acceptableUseURL =
                    URL(string: "https://www.adsbexchange.com/acceptable-use-policy/")
                {
                    Link(String(localized: .aboutAdsbExchangeAUP), destination: acceptableUseURL)
                }
            }

            Section(String(localized: .aboutGeographicData)) {
                Text(.aboutGeographicDataDescription)
                    .foregroundStyle(.secondary)
                if let naturalEarthURL = URL(string: "https://www.naturalearthdata.com/") {
                    Link(String(localized: .aboutNaturalEarth), destination: naturalEarthURL)
                }
                if let naturalEarthTermsURL =
                    URL(string: "https://www.naturalearthdata.com/about/terms-of-use/")
                {
                    Link(
                        String(localized: .aboutNaturalEarthTerms),
                        destination: naturalEarthTermsURL,
                    )
                }
            }

            Section(String(localized: .aboutLibraries)) {
                if credits.libraries.isEmpty {
                    Label(
                        String(localized: .aboutCreditsUnavailable),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(credits.libraries) { credit in
                        SoftwareCreditLink(credit: credit)
                    }
                }
            }

            Section(String(localized: .aboutDevelopmentTools)) {
                if credits.developmentTools.isEmpty {
                    Text(.aboutNoDevelopmentTools)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(credits.developmentTools) { credit in
                        SoftwareCreditLink(credit: credit)
                    }
                }
            }
        }
        .navigationTitle(Text(.aboutTitle))
        .navigationDestination(for: SoftwareCredit.self, destination: SoftwareCreditDetailView.init)
    }
}
