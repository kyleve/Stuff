import Testing
@testable import WhereUI

/// Verifies the pure place-name formatting that `LocationNamer` layers over the
/// system geocoder: city qualified by country, with sensible fallbacks when
/// only one piece is known.
struct PlaceComponentsTests {
    @Test func cityIsQualifiedByCountry() {
        let place = PlaceComponents(city: "Paris", country: "France")
        #expect(place.displayName == "Paris, France")
    }

    @Test func fallsBackToCountryWhenCityIsUnknown() {
        let place = PlaceComponents(city: nil, country: "United States")
        #expect(place.displayName == "United States")
    }

    @Test func fallsBackToCityWhenCountryIsUnknown() {
        let place = PlaceComponents(city: "Reykjavík", country: nil)
        #expect(place.displayName == "Reykjavík")
    }

    @Test func nothingKnownResolvesToNil() {
        let place = PlaceComponents(city: nil, country: nil)
        #expect(place.displayName == nil)
    }
}
