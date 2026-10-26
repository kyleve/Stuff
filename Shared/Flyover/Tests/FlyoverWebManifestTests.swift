#if DEBUG
    @testable import Flyover
    import Foundation
    import Testing

    struct FlyoverWebManifestTests {
        @Test func sharedWireFixtureRoundTripsWithoutLosingFields() throws {
            let url = try #require(Bundle(for: BundleToken.self).url(
                forResource: "manifest-v1",
                withExtension: "json",
            ))
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(FlyoverWebManifest.self, from: data)
            let encoded = try JSONEncoder().encode(manifest)
            let original = try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            let roundTrip = try #require(JSONSerialization
                .jsonObject(with: encoded) as? NSDictionary)
            #expect(original == roundTrip)
            let profile = try #require(manifest.profiles.first)
            #expect(profile.viewportSize == FlyoverWebManifest
                .Size(FlyoverCaptureProfile.phoneLight.profileSize))
        }

        private final class BundleToken {}
    }
#endif
