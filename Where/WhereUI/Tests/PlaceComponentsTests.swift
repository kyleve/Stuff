import Testing
@testable import WhereUI

/// Verifies the pure place-name formatting that `LocationNamer` layers over the
/// system geocoder: city preferred, qualified by country, with sensible
/// fallbacks.
struct PlaceComponentsTests {
    @Test func cityIsQualifiedByCountry() {
        let place = PlaceComponents(
            locality: "Paris",
            area: "Île-de-France",
            country: "France",
        )
        #expect(place.displayName == "Paris, France")
    }

    @Test func fallsBackToAreaWhenCityIsUnknown() {
        let place = PlaceComponents(
            locality: nil,
            area: "California",
            country: "United States",
        )
        #expect(place.displayName == "California, United States")
    }

    @Test func countryOnlyWhenThatIsAllWeKnow() {
        let place = PlaceComponents(locality: nil, area: nil, country: "Japan")
        #expect(place.displayName == "Japan")
    }

    @Test func nothingKnownResolvesToNil() {
        let place = PlaceComponents(locality: nil, area: nil, country: nil)
        #expect(place.displayName == nil)
    }
}
