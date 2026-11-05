import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingHistorySelectionTests {
    @Test func removedWholeDayChoiceKeepsItsLogicalDateAcrossAnEmptyGap() throws {
        let day = CalendarDay(year: 2001, month: 1, day: 1)
        let choice = try HistoryDecision(
            id: RecordingAssessmentTestSupport.decisionID(50),
            author: RecordingAssessmentTestSupport.first,
            periods: [RecordingAssessmentTestSupport.period(0, 86400)],
            scope: .recordingDay(deviceID: RecordingAssessmentTestSupport.first, day: day),
            action: .select(RecordingAssessmentTestSupport.first),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve(
            [],
            controls: [.source(choice)],
            removals: [RecordingControlSelectionTestSupport.removal(at: 600)],
            end: 86400,
        )
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.days == .known([day]))
        #expect(result.issues.first?.sampleIDs.isEmpty == true)
    }

    @Test func concurrentWholeDayChoicesKeepBothLogicalDatesWithoutGPS() throws {
        let firstDay = CalendarDay(year: 2001, month: 1, day: 1)
        let secondDay = CalendarDay(year: 2001, month: 1, day: 2)
        let first = try HistoryDecision(
            id: RecordingAssessmentTestSupport.decisionID(51),
            author: RecordingAssessmentTestSupport.first,
            periods: [RecordingAssessmentTestSupport.period(0, 86400)],
            scope: .recordingDay(deviceID: RecordingAssessmentTestSupport.first, day: firstDay),
            action: .select(RecordingAssessmentTestSupport.first),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        let second = try HistoryDecision(
            id: RecordingAssessmentTestSupport.decisionID(52),
            author: RecordingAssessmentTestSupport.second,
            periods: [RecordingAssessmentTestSupport.period(21600, 108_000)],
            scope: .recordingDay(deviceID: RecordingAssessmentTestSupport.second, day: secondDay),
            action: .select(RecordingAssessmentTestSupport.second),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve(
            [],
            controls: [.source(first), .source(second)],
            start: 36000,
            end: 37000,
        )
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.days == .known([firstDay, secondDay]))
    }

    @Test func clippingAControlConflictPreservesItsBoundedEvidenceAndKnownDay() throws {
        let observations = try RecordingAssessmentTestSupport.track(moving: true)
        let controls: [RecordingControl] = try [
            .source(RecordingAssessmentTestSupport.decision(40, end: 1201)),
            .source(RecordingAssessmentTestSupport.decision(
                41,
                end: 1201,
                action: .select(RecordingAssessmentTestSupport.second),
            )),
        ]
        let full = try RecordingHistorySelectionTestSupport.resolve(
            observations,
            controls: controls,
        )
        let clipped = try RecordingHistorySelectionTestSupport.resolve(
            observations,
            controls: controls,
            start: 300,
            end: 400,
        )
        let issue = try #require(clipped.issues.first)
        let original = try #require(full.issues.first { $0.period.contains(issue.period.start) })
        #expect(issue.days == original.days)
        #expect(issue.sampleIDs == original.sampleIDs)
        #expect(issue.sampleIDs == Set(observations.prefix(2).map(\.sample.id)))
        #expect(try issue.days == .known([#require(observations.first?.recordingDay.day)]))
        #expect(clipped.contributions.isEmpty)
    }

    @Test func aMidnightBracketCannotCountTwoDatesForTheSameOverlappingEvidence() throws {
        let observations = try RecordingHistorySelectionTestSupport.midnightObservations()
        let result = try RecordingHistorySelectionTestSupport.resolve(observations, end: 1)
        #expect(result.contributions.isEmpty)
        #expect(result.issues.count == 1)
        #expect(result.issues.first?.days == .known([
            CalendarDay(year: 2000, month: 12, day: 31),
            CalendarDay(year: 2001, month: 1, day: 1),
        ]))
    }

    @Test func strongMovementSelectsOneTrackIncludingItsFinalObservation() throws {
        let moving = try RecordingAssessmentTestSupport.track(moving: true)
        let stationary = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: false,
            region: .newYork,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve(moving + stationary)
        #expect(Set(result.contributions) == Set(moving))
        #expect(result.issues.isEmpty)
        #expect(result.segments.allSatisfy {
            $0.resolution == .automatic(.movingOverStationary(RecordingAssessmentTestSupport.first))
        })
    }

    @Test func ambiguousTracksExcludeOnlyTheirDisputedContribution() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: true,
            region: .newYork,
        )
        let later = try RecordingAssessmentTestSupport.observation(seconds: 7200)
        let result = try RecordingHistorySelectionTestSupport.resolve(
            first + second + [later],
            end: 7201,
        )
        #expect(result.contributions == [later])
        #expect(!result.issues.isEmpty)
        #expect(try Set(result.issues.flatMap(\.days.candidates)) ==
            [#require(later.recordingDay.day)])
        #expect(result.issues
            .allSatisfy { $0.period.end <= RecordingAssessmentTestSupport.time(1201) })
    }

    @Test func sourceChoiceBypassesAnIgnoreAndNeverFillsItsGaps() throws {
        let first = try RecordingAssessmentTestSupport.observation(seconds: 0)
        let other = try RecordingAssessmentTestSupport.observation(
            deviceID: RecordingAssessmentTestSupport.second,
            seconds: 600,
            region: .newYork,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve([first, other], controls: [
            .source(RecordingAssessmentTestSupport.decision(10, end: 1201)),
            .ignore(RecordingControlsTestSupport.ignore(11)),
        ])
        #expect(result.contributions == [first])
        #expect(result.issues.isEmpty)
    }

    @Test func removalLeavesTheChosenPortionUnresolvedWithoutFallback() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: false,
            region: .newYork,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve(first + second, controls: [
            .source(RecordingAssessmentTestSupport.decision(10, end: 1201)),
        ], removals: [RecordingControlSelectionTestSupport.removal(at: 600)])
        #expect(result.contributions == [first[0]])
        #expect(result.issues.count == 2)
        #expect(result.issues.first?
            .problem == .controls(.selectedDeviceRemoved(RecordingAssessmentTestSupport.first)))
        #expect(result.issues.first?.period.start == RecordingAssessmentTestSupport.time(600))
    }

    @Test func missingIgnoreDependenciesCannotPromoteTheCompetingDevice() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            moving: false,
        )
        let ignored = try RecordingControlsTestSupport.ignore(12, predecessors: [
            .init(rawValue: RecordingAssessmentTestSupport.decisionID(11).rawValue),
        ])
        let unresolved = try RecordingHistorySelectionTestSupport.resolve(
            first + second,
            controls: [.ignore(ignored)],
        )
        #expect(unresolved.contributions.isEmpty)
        #expect(!unresolved.issues.isEmpty)
        let absent = try RecordingHistorySelectionTestSupport.resolve(
            second,
            controls: [.ignore(ignored)],
        )
        #expect(Set(absent.contributions) == Set(second))
        #expect(absent.issues.isEmpty)
    }

    @Test func resolvedDayConflictRetainsBothCandidateDatesUntilAChoice() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: false)
        let zone = try #require(TimeZone(secondsFromGMT: -3600))
        let second = try [0.0, 600, 1200].map {
            try RecordingAssessmentTestSupport.observation(
                deviceID: RecordingAssessmentTestSupport.second,
                seconds: $0,
                timeZone: zone,
            )
        }
        let result = try RecordingHistorySelectionTestSupport.resolve(first + second)
        #expect(result.contributions.isEmpty)
        let days = Set((first + second).compactMap(\.recordingDay.day))
        #expect(days.count == 2)
        #expect(result.issues.allSatisfy { $0.days == .known(days) })
        let selected = try RecordingHistorySelectionTestSupport.resolve(first + second, controls: [
            .source(RecordingAssessmentTestSupport.decision(
                20,
                end: 1201,
                action: .select(RecordingAssessmentTestSupport.second),
            )),
        ])
        #expect(Set(selected.contributions) == Set(second))
        #expect(selected.issues.isEmpty)
    }

    @Test func unresolvedCalendarContextRequiresInputAndPreservesKnownPresenceElsewhere() throws {
        let unknown = try RecordingAssessmentTestSupport.observation(
            seconds: 0,
            assignment: .unresolved,
        )
        let competing = try RecordingAssessmentTestSupport.observation(
            deviceID: RecordingAssessmentTestSupport.second,
            seconds: 0,
        )
        let later = try RecordingAssessmentTestSupport.observation(seconds: 7200)
        let result = try RecordingHistorySelectionTestSupport.resolve(
            [unknown, competing, later],
            end: 7201,
        )
        #expect(result.contributions == [later])
        #expect(result.issues.count == 1)
        #expect(try result.issues.first?
            .days == .unassigned(known: [#require(competing.recordingDay.day)]))
        let single = try RecordingHistorySelectionTestSupport.resolve([unknown])
        #expect(single.contributions.isEmpty)
        #expect(single.issues.first?.days == .unassigned(known: []))
    }

    @Test func unknownGeographyAloneDoesNotBecomeAConflict() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: false, region: nil)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            moving: false,
            region: nil,
        )
        let result = try RecordingHistorySelectionTestSupport.resolve(first + second)
        #expect(Set(result.contributions) == Set(first + second))
        #expect(result.issues.isEmpty)
        #expect(result.segments.allSatisfy {
            $0.resolution == .automatic(.uncertain([
                RecordingAssessmentTestSupport.first,
                RecordingAssessmentTestSupport.second,
            ]))
        })
    }

    @Test func explicitMultiRegionCorrectionsRemainSpecificAndCanAgree() throws {
        let raw = try RecordingAssessmentTestSupport.track(moving: false)
            + RecordingAssessmentTestSupport.track(
                deviceID: RecordingAssessmentTestSupport.second,
                longitude: -74,
                moving: false,
            )
        let geography = try RecordingGeography(
            knownRegions: [.california, .newYork],
            includesUnknownPresence: false,
        )
        let corrected = try raw.map {
            try RecordingObservation(
                sample: $0.sample,
                recordingDay: $0.recordingDay,
                geography: geography,
            )
        }
        let result = try RecordingHistorySelectionTestSupport.resolve(corrected)
        #expect(Set(result.contributions) == Set(corrected))
        #expect(result.issues.isEmpty)
        #expect(result.segments.allSatisfy {
            $0.resolution == .automatic(.agreement([
                RecordingAssessmentTestSupport.first,
                RecordingAssessmentTestSupport.second,
            ]))
        })
    }

    @Test func orderDuplicationAndQueryClippingKeepTheSameSelection() throws {
        let observations = try RecordingAssessmentTestSupport.track(moving: true)
            + RecordingAssessmentTestSupport.track(
                deviceID: RecordingAssessmentTestSupport.second,
                longitude: -74,
                moving: false,
                region: .newYork,
            )
        let result = try RecordingHistorySelectionTestSupport.resolve(observations)
        #expect(try result == RecordingHistorySelectionTestSupport
            .resolve(observations.reversed() + observations))
        let narrow = try RecordingHistorySelectionTestSupport.resolve(
            observations,
            start: 600,
            end: 900,
        )
        #expect(narrow.contributions == result.contributions.filter {
            $0.sample.timestamp >= RecordingAssessmentTestSupport.time(600) && $0.sample
                .timestamp < RecordingAssessmentTestSupport.time(900)
        })
        #expect(narrow.issues.isEmpty)
    }
}
