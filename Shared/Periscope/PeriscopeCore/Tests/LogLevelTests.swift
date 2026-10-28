import Foundation
import os
import PeriscopeCore
import Testing

struct LogLevelTests {
    @Test func standardLadderOrdersBySeverity() {
        let ladder = LogLevel.standardLevels
        #expect(ladder == ladder.sorted())
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .notice)
        #expect(LogLevel.notice < .warning)
        #expect(LogLevel.warning < .error)
        #expect(LogLevel.error < .fault)
    }

    @Test func customLevelSlotsBetweenStandardLevels() {
        let audit = LogLevel(name: "audit", severity: 450)
        #expect(LogLevel.warning < audit)
        #expect(audit < LogLevel.error)
    }

    @Test func orderingComparesSeverityAlone() {
        let renamed = LogLevel(name: "renamed", severity: LogLevel.warning.severity)
        #expect(!(renamed < LogLevel.warning))
        #expect(!(LogLevel.warning < renamed))
        #expect(renamed != LogLevel.warning)
    }

    @Test(arguments: [
        (LogLevel.debug, OSLogType.debug),
        (LogLevel.info, OSLogType.info),
        (LogLevel.notice, OSLogType.default),
        (LogLevel.warning, OSLogType.default),
        (LogLevel.error, OSLogType.error),
        (LogLevel.fault, OSLogType.fault),
    ])
    func standardLevelsMapToOSLogTypes(level: LogLevel, expected: OSLogType) {
        #expect(level.osLogType == expected)
    }

    @Test func customLevelsInheritOSLogTypeBySeverityBand() {
        #expect(LogLevel(name: "trace", severity: 50).osLogType == .debug)
        #expect(LogLevel(name: "audit", severity: 450).osLogType == .default)
        #expect(LogLevel(name: "critical", severity: 550).osLogType == .error)
        #expect(LogLevel(name: "meltdown", severity: 900).osLogType == .fault)
    }

    @Test func customLevelsCanOverrideTheirOSLogType() {
        let audit = LogLevel(name: "audit", severity: 450, osLogType: .error)
        #expect(audit.osLogType == .error)

        // The mapping routes OSLog mirroring; it is not part of identity.
        let banded = LogLevel(name: "audit", severity: 450)
        #expect(audit == banded)
        #expect(audit.hashValue == banded.hashValue)
    }

    @Test func roundTripsThroughCodable() throws {
        let level = LogLevel(name: "audit", severity: 450)
        let data = try JSONEncoder().encode(level)
        let decoded = try JSONDecoder().decode(LogLevel.self, from: data)
        #expect(decoded == level)
    }

    @Test func decodedLevelsRederiveTheBandDefaultOSLogType() throws {
        // The OSLog mapping only routes live mirroring, so it isn't
        // persisted — a custom mapping decodes back to the band default.
        let custom = LogLevel(name: "audit", severity: 450, osLogType: .error)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(LogLevel.self, from: data)
        #expect(decoded == custom)
        #expect(decoded.osLogType == .default)
    }
}
