import CreditKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct ThrowAboutView: View {
    let session: ThrowSession

    var body: some View {
        let credits = SoftwareCreditsPresentation(state: session.softwareCreditsState)
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
                if let flightradar24URL = URL(string: "https://fr24api.flightradar24.com") {
                    Link(String(localized: .aboutFlightradar24), destination: flightradar24URL)
                }
                if let aircraftDatabaseURL =
                    URL(string: "https://github.com/Mictronics/aircraft-database")
                {
                    Link(
                        String(localized: .aboutAircraftTypeDatabase),
                        destination: aircraftDatabaseURL,
                    )
                }
                Text(.aboutAircraftTypeDatabaseCredit)
                    .foregroundStyle(.secondary)
                if let adsbdbURL = URL(string: "https://www.adsbdb.com/") {
                    Link(String(localized: .aboutAdsbdb), destination: adsbdbURL)
                }
                Text(.aboutRouteDataCredit)
                    .foregroundStyle(.secondary)
                if let ourAirportsURL = URL(string: "https://ourairports.com/data/") {
                    Link(String(localized: .aboutOurAirports), destination: ourAirportsURL)
                }
                Text(.aboutAirportGeometryCredit)
                    .foregroundStyle(.secondary)
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
                if let censusGeographyURL = URL(
                    string: "https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.2025.html",
                ) {
                    Link(String(localized: .aboutUSCensusBureau), destination: censusGeographyURL)
                }
                if let censusTermsURL = URL(
                    string: "https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2025/TGRSHP2025_TechDoc_Ch1.pdf",
                ) {
                    Link(String(localized: .aboutUSCensusTerms), destination: censusTermsURL)
                }
            }

            switch credits {
                case let .loaded(credits):
                    Section(String(localized: .aboutLibraries)) {
                        if credits.libraries.isEmpty {
                            Text(.aboutNoLibraries)
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
                case .unavailable:
                    Section(String(localized: .aboutSoftware)) {
                        Label(
                            String(localized: .aboutCreditsUnavailable),
                            systemSymbol: .exclamationmarkTriangle,
                        )
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .navigationTitle(Text(.aboutTitle))
        .navigationDestination(for: SoftwareCredit.self, destination: SoftwareCreditDetailView.init)
    }
}

#if DEBUG
    extension ThrowAboutView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Loaded credits",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 0.75),
            ) {
                NavigationStack {
                    ThrowAboutView(session: .loadedSoftwareCreditsSnapshotFixture())
                }
                .throwBroadwayRoot()
            }
            SnapshotCase(
                name: "Credits unavailable",
                configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 0.75),
            ) {
                NavigationStack {
                    ThrowAboutView(session: .unavailableSoftwareCreditsSnapshotFixture())
                }
                .throwBroadwayRoot()
            }
        }
    }

    #Preview {
        ThrowAboutView.snapshotPreviews
    }
#endif
