import Foundation
import Testing
import WhereCore

@Test
func taxDayCalculatorCountsMultipleJurisdictionsPerDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let calculator = TaxDayCalculator(calendar: calendar)
    let samples = [
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_735_689_600),
            jurisdiction: .california,
        ),
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_735_725_600),
            jurisdiction: .newYork,
        ),
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_735_776_000),
            jurisdiction: .california,
        ),
    ]

    let records = calculator.makeDailyRecords(from: samples)
    let counts = calculator.countDaysByJurisdiction(from: records)

    #expect(records.count == 2)
    #expect(records[0].jurisdictions == [.california, .newYork])
    #expect(counts[.california] == 2)
    #expect(counts[.newYork] == 1)
}

@Test
func taxDayCalculatorKeepsUnknownDaysOutOfTaxTotals() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let calculator = TaxDayCalculator(calendar: calendar)
    let samples = [
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_736_035_200),
            jurisdiction: .unknown,
        ),
    ]

    let records = calculator.makeDailyRecords(from: samples)
    let counts = calculator.countDaysByJurisdiction(from: records)

    #expect(records.count == 1)
    #expect(records[0].jurisdictions == [.unknown])
    #expect(counts.isEmpty)
}

@Test
func yearLedgerBuilderUsesCorrectionsToOverrideTrackedJurisdictions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let builder = YearLedgerBuilder(calendar: calendar)
    let year = 2026
    let samples = [
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_767_715_200),
            jurisdiction: .unknown,
        ),
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_767_718_800),
            jurisdiction: .california,
        ),
    ]
    let manualEntries = [
        ManualLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_767_720_000),
            jurisdiction: .newYork,
            note: "Boarding pass attached",
            kind: .correction,
        ),
    ]

    let ledgers = builder.makeLedgers(
        year: year,
        samples: samples,
        manualEntries: manualEntries,
    )
    let summary = builder.makeYearSummary(year: year, ledgers: ledgers)

    #expect(ledgers.count == 1)
    #expect(ledgers[0].trackedJurisdictions == [.california, .unknown])
    #expect(ledgers[0].finalJurisdictions == [.newYork])
    #expect(ledgers[0].note == "Manual correction applied")
    #expect(summary.totalsByJurisdiction[.newYork] == 1)
    #expect(summary.totalsByJurisdiction[.california] == nil)
    #expect(summary.unknownDayCount == 0)
}

@Test
func yearLedgerBuilderUsesSupplementalEntriesAsAdditiveEvidence() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

    let builder = YearLedgerBuilder(calendar: calendar)
    let year = 2026
    let samples = [
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 1_767_456_000),
            jurisdiction: .california,
        ),
    ]
    let manualEntries = [
        ManualLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_767_459_600),
            jurisdiction: .newYork,
            note: "Flight evidence added",
            kind: .supplemental,
        ),
    ]

    let ledgers = builder.makeLedgers(
        year: year,
        samples: samples,
        manualEntries: manualEntries,
    )
    let summary = builder.makeYearSummary(year: year, ledgers: ledgers)

    #expect(ledgers.count == 1)
    #expect(ledgers[0].finalJurisdictions == [.california, .newYork])
    #expect(ledgers[0].note == "Multiple jurisdictions logged")
    #expect(summary.totalsByJurisdiction[.california] == 1)
    #expect(summary.totalsByJurisdiction[.newYork] == 1)
}
