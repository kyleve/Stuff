import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct ElsewhereResolverTests {
    @Test func expandsCanadaAndTheEuropeanUnionUsingExistingCatalogIdentities() async throws {
        let input = ElsewhereTestSupport.input(samples: [
            ElsewhereTestSupport.sample(Coordinate(latitude: 49.2827, longitude: -123.1207)),
            ElsewhereTestSupport.sample(Coordinate(latitude: 48.8566, longitude: 2.3522)),
        ])
        let result = try await ElsewhereResolver().resolve(input)
        #expect(result.regions.map(\.region) == [.canada, .europeanUnion])
        #expect(result.regions.allSatisfy { $0.days.count == 1 && $0.locations.count == 1 })
        #expect(input.report.totals == [.other: 1])
    }

    @Test func namesUntrackedRegionsAndCountsDistinctDaysWithoutChangingTheReport() async throws {
        let input = ElsewhereTestSupport.input(samples: [
            ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas),
            ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas),
            ElsewhereTestSupport.sample(ElsewhereTestSupport.portland),
            ElsewhereTestSupport.sample(ElsewhereTestSupport.portland, day: 2),
            ElsewhereTestSupport.sample(ElsewhereTestSupport.ocean, day: 3),
        ])
        let result = try await ElsewhereResolver().resolve(input)
        let nevada = try #require(Region(rawValue: "us-NV"))
        let oregon = try #require(Region(rawValue: "us-OR"))
        let byRegion = Dictionary(uniqueKeysWithValues: result.regions.map { ($0.region, $0) })
        #expect(byRegion[nevada]?.days.count == 1)
        #expect(byRegion[oregon]?.days.count == 2)
        #expect(byRegion[.other]?.days.count == 1)
        #expect(byRegion[nevada]?.locations.flatMap(\.points).count == 2)
        #expect(byRegion[oregon]?.locations.map(\.day) == byRegion[oregon]?.days.map(\.day))
        #expect(byRegion[nevada]?.representativeCoordinate == ElsewhereTestSupport.vegas)
        #expect(input.report.totals == [.other: 3])
        #expect(byRegion[nevada]?.days.first?.regions == [.other])
    }

    @Test func authoritativeDaysAndManualOtherAreNotReinterpreted() async throws {
        let day = CalendarDay(year: 2026, month: 6, day: 1)
        let input = ElsewhereTestSupport.input(
            samples: [ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)],
            manualDays: [DayPresence(day: day, regions: [.other], isAuthoritative: true)],
        )
        let result = try await ElsewhereResolver().resolve(input)
        #expect(result.regions.map(\.region) == [.other])
        #expect(result.regions.first?.days.count == 1)
        #expect(result.regions.first?.locations.flatMap(\.points).count == 1)
        #expect(result.regions.first?.representativeCoordinate == nil)

        let replaced = ElsewhereTestSupport.input(
            samples: [ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)],
            manualDays: [DayPresence(day: day, regions: [.california], isAuthoritative: true)],
        )
        #expect(try await ElsewhereResolver().resolve(replaced).regions.isEmpty)
    }

    @Test func manualOnlyAndAdditiveUnknownPresenceStayVisible() async throws {
        let day = CalendarDay(year: 2026, month: 6, day: 1)
        let input = ElsewhereTestSupport.input(
            samples: [ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)],
            manualDays: [
                DayPresence(day: day, regions: [.other]),
                DayPresence(day: CalendarDay(year: 2026, month: 6, day: 2), regions: [.canada]),
            ],
        )
        let result = try await ElsewhereResolver().resolve(input)
        let nevada = try #require(Region(rawValue: "us-NV"))
        #expect(Set(result.regions.map(\.region)) == [nevada, .canada, .other])
        #expect(result.regions.first { $0.region == .canada }?.locations.isEmpty == true)
        #expect(result.regions.first { $0.region == .other }?.days.map(\.day) == [day])
    }

    @Test(arguments: [Set<Region>(), [.other], [.canada], [.california]])
    func explicitSampleCorrectionsWin(regions: Set<Region>) async throws {
        let sample = ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)
        let correction = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: sample.id,
            updatedAt: sample.timestamp,
            replacementRegions: regions,
        )
        let input = ElsewhereTestSupport.input(samples: [sample], revisions: [correction])
        let result = try await ElsewhereResolver().resolve(input)
        #expect(Set(result.regions.map(\.region)) == regions.subtracting(input.primaryRegions))
    }

    @Test func newerResetRestoresCatalogResolution() async throws {
        let sample = ElsewhereTestSupport.sample(ElsewhereTestSupport.vegas)
        let older = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: sample.id,
            updatedAt: sample.timestamp,
            replacementRegions: [.other],
        )
        let reset = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: sample.id,
            updatedAt: sample.timestamp.addingTimeInterval(1),
            replacementRegions: nil,
        )
        let input = ElsewhereTestSupport.input(samples: [sample], revisions: [reset, older])
        let result = try await ElsewhereResolver().resolve(input)
        #expect(try result.regions.map(\.region) == [#require(Region(rawValue: "us-NV"))])
    }

    @Test func primarySelectionExcludesManualRegions() async throws {
        let day = CalendarDay(year: 2026, month: 6, day: 1)
        let input = ElsewhereTestSupport.input(
            manualDays: [DayPresence(day: day, regions: [.california, .newYork, .canada, .other])],
            primaryRegions: [.california, .newYork, .canada],
        )
        let result = try await ElsewhereResolver().resolve(input)
        #expect(result.regions.map(\.region) == [.other])
    }
}
