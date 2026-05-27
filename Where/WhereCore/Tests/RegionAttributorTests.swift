import Testing
import WhereCore

struct RegionAttributorTests {
    let attributor = RegionAttributor.shared

    // MARK: - California

    @Test func sanFrancisco_isCalifornia() {
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        #expect(attributor.region(at: sf) == .california)
    }

    @Test func losAngeles_isCalifornia() {
        let la = Coordinate(latitude: 34.0522, longitude: -118.2437)
        #expect(attributor.region(at: la) == .california)
    }

    @Test func renoIsOutsideCalifornia() {
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        #expect(attributor.region(at: reno) != .california)
    }

    @Test func tijuanaIsOutsideCalifornia() {
        let tijuana = Coordinate(latitude: 32.5149, longitude: -117.0382)
        #expect(attributor.region(at: tijuana) != .california)
    }

    // MARK: - New York

    @Test func newYorkCity_isNewYork() {
        let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
        #expect(attributor.region(at: nyc) == .newYork)
    }

    @Test func buffalo_isNewYork() {
        let buffalo = Coordinate(latitude: 42.8864, longitude: -78.8784)
        #expect(attributor.region(at: buffalo) == .newYork)
    }

    @Test func newark_isOutsideNewYork() {
        let newark = Coordinate(latitude: 40.7357, longitude: -74.1724)
        #expect(attributor.region(at: newark) != .newYork)
    }

    // MARK: - Canada

    @Test func toronto_isCanada() {
        let toronto = Coordinate(latitude: 43.6532, longitude: -79.3832)
        #expect(attributor.region(at: toronto) == .canada)
    }

    @Test func montreal_isCanada() {
        let montreal = Coordinate(latitude: 45.5017, longitude: -73.5673)
        #expect(attributor.region(at: montreal) == .canada)
    }

    @Test func buffalo_isNotCanada() {
        let buffalo = Coordinate(latitude: 42.8864, longitude: -78.8784)
        #expect(attributor.region(at: buffalo) != .canada)
    }

    // MARK: - European Union

    @Test func paris_isEuropeanUnion() {
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        #expect(attributor.region(at: paris) == .europeanUnion)
    }

    @Test func berlin_isEuropeanUnion() {
        let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
        #expect(attributor.region(at: berlin) == .europeanUnion)
    }

    @Test func london_isOutsideEuropeanUnion() {
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        #expect(attributor.region(at: london) != .europeanUnion)
    }

    // MARK: - Other

    @Test func chicago_isOther() {
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298)
        #expect(attributor.region(at: chicago) == .other)
    }

    @Test func tokyo_isOther() {
        let tokyo = Coordinate(latitude: 35.6762, longitude: 139.6503)
        #expect(attributor.region(at: tokyo) == .other)
    }
}
