import PeriscopeCore
@testable import PeriscopeTools
import Testing

/// Covers the two spellings of a level's name the tools render. `LogLevel` is a
/// struct whose `name` is free-form, so these hold for a custom level too — not
/// just the built-in five.
struct LogLevelDisplayTests {
    @Test func namesALevelForBadgesAndFilters() {
        #expect(LogLevel.debug.displayName == "Debug")
        #expect(LogLevel.warning.displayName == "Warning")
        #expect(LogLevel.debug.badgeLabel == "DEBUG")
        #expect(LogLevel.warning.badgeLabel == "WARNING")
    }

    @Test func namesACustomLevelFromItsOwnName() {
        let level = LogLevel(name: "audit", severity: 42)
        #expect(level.displayName == "Audit")
        #expect(level.badgeLabel == "AUDIT")
    }
}
