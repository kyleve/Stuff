@testable import BroadwayCore
import Testing

private enum Palette: String, BTheme {
    static let defaultValue: Self = .light

    case light, dark
}

private enum Typography: String, BTheme {
    static let defaultValue: Self = .standard

    case standard, compact
}

struct BThemesTests {
    // MARK: - Default Value

    @Test("Unset theme returns defaultValue")
    func unsetReturnsDefault() {
        let themes = BThemes()
        #expect(themes[Palette.self] == .light)
    }

    // MARK: - Set / Get

    @Test("Set and get roundtrip")
    func setGetRoundtrip() {
        var themes = BThemes()
        themes[Palette.self] = .dark
        #expect(themes[Palette.self] == .dark)
    }

    @Test("Setting a theme twice uses the latest value")
    func overwrite() {
        var themes = BThemes()
        themes[Palette.self] = .dark
        themes[Palette.self] = .light
        #expect(themes[Palette.self] == .light)
    }

    @Test("Multiple theme types coexist")
    func multipleTypes() {
        var themes = BThemes()
        themes[Palette.self] = .dark
        themes[Typography.self] = .compact

        #expect(themes[Palette.self] == .dark)
        #expect(themes[Typography.self] == .compact)
    }

    // MARK: - Equatable

    @Test("Two empty instances are equal")
    func emptyEquality() {
        #expect(BThemes() == BThemes())
    }

    @Test("Instances with the same content are equal")
    func sameContentEqual() {
        var a = BThemes()
        a[Palette.self] = .dark
        var b = BThemes()
        b[Palette.self] = .dark
        #expect(a == b)
    }

    @Test("Instances with different content are not equal")
    func differentContentNotEqual() {
        var a = BThemes()
        a[Palette.self] = .light
        var b = BThemes()
        b[Palette.self] = .dark
        #expect(a != b)
    }

    // MARK: - Value Semantics

    @Test("Mutating a copy does not affect the original")
    func copyIndependence() {
        var a = BThemes()
        a[Palette.self] = .dark
        var b = a
        b[Palette.self] = .light

        #expect(a[Palette.self] == .dark)
        #expect(b[Palette.self] == .light)
    }
}
