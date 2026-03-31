@testable import BroadwayCore
import Testing

private struct ScaleFactor: BTraitsValue {
    var value: Double
    static var defaultValue: Self {
        ScaleFactor(value: 1.0)
    }
}

struct BTraitsTests {
    // MARK: - Default Value

    @Test("Unset trait returns defaultValue")
    func defaultValue() {
        let traits = BTraits()
        #expect(traits[ScaleFactor.self].value == 1.0)
    }

    // MARK: - Set / Get

    @Test("Set and get roundtrip")
    func setGetRoundtrip() {
        var traits = BTraits()
        traits[ScaleFactor.self] = ScaleFactor(value: 2.0)
        #expect(traits[ScaleFactor.self].value == 2.0)
    }

    @Test("Setting a trait twice uses the latest value")
    func overwrite() {
        var traits = BTraits()
        traits[ScaleFactor.self] = ScaleFactor(value: 2.0)
        traits[ScaleFactor.self] = ScaleFactor(value: 3.0)
        #expect(traits[ScaleFactor.self].value == 3.0)
    }

    // MARK: - Accessibility Convenience

    @Test("Accessibility convenience accessor roundtrips")
    func accessibilityAccessor() {
        var traits = BTraits()
        let value = BAccessibility(isVoiceOverRunning: true)
        traits.accessibility = value
        #expect(traits.accessibility == value)
    }

    // MARK: - Equatable

    @Test("Two default instances are equal")
    func defaultEquality() {
        #expect(BTraits() == BTraits())
    }

    @Test("Instances with different values are not equal")
    func inequality() {
        var a = BTraits()
        a[ScaleFactor.self] = ScaleFactor(value: 2.0)
        #expect(a != BTraits())
    }

    // MARK: - Value Semantics

    @Test("Mutating a copy does not affect the original")
    func copyIndependence() {
        var a = BTraits()
        a[ScaleFactor.self] = ScaleFactor(value: 2.0)
        var b = a
        b[ScaleFactor.self] = ScaleFactor(value: 5.0)

        #expect(a[ScaleFactor.self].value == 2.0)
        #expect(b[ScaleFactor.self].value == 5.0)
    }
}
