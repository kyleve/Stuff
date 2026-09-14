import Foundation
import PortholeRuntime
import RegionKit
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct WherePortholeCapabilitiesTests {
    @Test func capturesStayBoundedAndDayReadsReuseOwnedChildren() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        let scope = try fixture.makeScope()
        let registry = fixture.registry
        let token = await registry.createScope(id: .init(rawValue: "investigation-test"))
        await registry.setEnabled(true)
        try await WherePortholeCapabilities.install(scope: scope, registry: registry, token: token)
        let roots = try await registry.objectReferences(in: token)
        let captureArguments = PortholeValue.object([
            "year": .integer(2025),
            "primaryRegions": .array([]),
            "driftThresholdMeters": .number(100),
        ])
        let first = try await registry.invoke(.init(
            id: UUID(),
            scope: token,
            capabilityID: .init(rawValue: "where.investigation.capture"),
            receiver: nil,
            arguments: captureArguments,
        ))
        let firstReference = try #require(first["$reference"]).decode(PortholeObjectReference.self)
        var days: [PortholeValue] = []
        for _ in 0 ..< 20 {
            try await days.append(registry.invoke(.init(
                id: UUID(),
                scope: token,
                capabilityID: .init(rawValue: "where.investigation.day"),
                receiver: nil,
                arguments: .object(["investigation": first, "day": .string("2025-01-01")]),
            )))
        }
        #expect(days
            .allSatisfy {
                $0["input"] == days.first?["input"] && $0["attributor"] == days.first?["attributor"]
            })
        #expect(try await registry.objectReferences(in: token).count == roots.count + 3)
        for _ in 0 ..< 6 {
            _ = try await registry.invoke(.init(
                id: UUID(),
                scope: token,
                capabilityID: .init(rawValue: "where.investigation.capture"),
                receiver: nil,
                arguments: captureArguments,
            ))
        }
        let retained = try await registry.objectReferences(in: token)
        #expect(retained.count == roots.count + 4)
        #expect(roots.allSatisfy { retained.contains($0) })
        await #expect(throws: PortholeError.unknownObject) { try await registry.resolve(
            firstReference,
            as: DataIssueInvestigation.self,
            in: token,
        ) }
        let input = try #require(days.first?["input"])
        await #expect(throws: PortholeError.unknownObject) { try await registry.decode(
            input,
            as: DataIssueInput.self,
            in: token,
        ) }
        await registry.invalidate(token)
    }

    @Test func ordinaryCapabilitiesExplainCopiedDriftWithoutChangingTheLiveScanner() async throws {
        let fixture = WherePortholeTestFixture(enabled: true)
        defer { fixture.removeFiles() }
        let drift = try await WherePortholeDriftFixture.make(preferences: fixture.preferences)
        let services = drift.scope.services
        let selectedIssueID = DataIssueID.borderDrift(day: drift.day)
        let liveIssues = try await services.resolution.issues(
            year: drift.day.year,
            primaryRegions: [.california],
            driftThresholdMeters: drift.thresholdMeters,
        )
        #expect(!liveIssues.contains { $0.id == selectedIssueID })
        let reportBefore = try await services.reports.yearReport(for: drift.day.year)
        let manualDaysBefore = try await services.reports.manualDays(inYear: drift.day.year)
        let scannerBefore = await services.resolution.diagnosticState
        guard case .cached = scannerBefore else {
            Issue.record("The fixture must warm the production scanner before investigation")
            return
        }

        let registry = fixture.registry
        let token = await registry.createScope(id: .init(rawValue: "ordinary-drift-investigation"))
        await registry.setEnabled(true)
        try await WherePortholeCapabilities.install(
            scope: drift.scope,
            registry: registry,
            token: token,
        )
        func invoke(_ capabilityID: PortholeSymbolID, arguments: PortholeValue) async throws
            -> PortholeValue
        {
            try await registry.invoke(.init(
                id: UUID(),
                scope: token,
                capabilityID: capabilityID,
                receiver: nil,
                arguments: arguments,
            ))
        }
        let scannerEvidenceBefore = try await invoke(
            .init(rawValue: "where.scanner.state"),
            arguments: .object([:]),
        )
        #expect(try scannerEvidenceBefore
            .decode(DataIssueScanner.DiagnosticState.self) == scannerBefore)
        let capture = try await invoke(
            .init(rawValue: "where.investigation.capture"),
            arguments: .object([
                "year": .integer(Int64(drift.day.year)),
                "primaryRegions": .array([.string(Region.california.rawValue)]),
                "driftThresholdMeters": .number(drift.thresholdMeters),
            ]),
        )
        let investigation = try await registry.decode(
            capture,
            as: DataIssueInvestigation.self,
            in: token,
        )
        let dayEvidence = try await invoke(
            .init(rawValue: "where.investigation.day"),
            arguments: .object(["investigation": capture, "day": .string(drift.day.description)]),
        )
        #expect(dayEvidence["evidenceKind"] == .string("observed current snapshot"))
        #expect(dayEvidence["day"] == .string(drift.day.description))
        #expect(try dayEvidence["capturedAt"] == .encoding(investigation.capturedAt))
        #expect(try #require(dayEvidence["samples"])
            .decode([LocationSample].self) == [drift.sample])
        #expect(try #require(dayEvidence["presence"]).decode(DayPresence.self) == DayPresence(
            day: drift.day,
            regions: [.other],
        ))
        #expect(try #require(dayEvidence["otherCoordinates"])
            .decode([Coordinate].self) == [drift.sample.coordinate])
        #expect(try #require(dayEvidence["attribution"]).decode([Region].self) == [.other])
        #expect(try #require(dayEvidence["primaryRegions"]).decode([Region].self) == [.california])
        #expect(dayEvidence["driftThresholdMeters"] == .number(drift.thresholdMeters))
        #expect(dayEvidence["timeZone"] == .string("GMT"))
        #expect(try #require(dayEvidence["dismissedIssueIDs"])
            .decode(Set<DataIssueID>.self) == [selectedIssueID])

        let inputEvidence = try #require(dayEvidence["input"])
        let input = try await registry.decode(inputEvidence, as: DataIssueInput.self, in: token)
        let attributionEvidence = try #require(dayEvidence["attributor"])
        let attributor = try await registry.decode(
            attributionEvidence,
            as: RegionAttributor.self,
            in: token,
        )
        #expect(input.daySamples.samples(on: drift.day) == [drift.sample])
        #expect(input.primaryRegions == [.california])
        #expect(input.driftThresholdMeters == drift.thresholdMeters)
        #expect(attributor.region(at: drift.sample.coordinate) == .other)
        #expect(try #require(dayEvidence["loadedRegions"]).decode([Region].self) == attributor
            .loadedRegions)

        let flight = try await invoke(
            .init(rawValue: "where.investigation.replay"),
            arguments: .object([
                "investigation": capture,
                "category": .string(DataIssueCategory.flightDay.rawValue),
            ]),
        )
        #expect(flight["evidenceKind"] == .string("reproduced"))
        #expect(flight["issues"] == .array([]))
        let replayArguments = PortholeValue.object([
            "investigation": capture,
            "category": .string(DataIssueCategory.borderDrift.rawValue),
        ])
        let replay = try await invoke(
            .init(rawValue: "where.investigation.replay"),
            arguments: replayArguments,
        )
        #expect(replay["evidenceKind"] == .string("reproduced"))
        guard case let .array(issues) = replay["issues"] else {
            Issue.record("The ordinary replay response must contain issue evidence")
            return
        }
        #expect(issues.count == 1)
        let issueEvidence = try #require(issues.first)
        #expect(try #require(issueEvidence["id"]).decode(DataIssueID.self) == selectedIssueID)
        #expect(issueEvidence["category"] == .string(DataIssueCategory.borderDrift.rawValue))
        #expect(issueEvidence["day"] == .string(drift.day.description))
        #expect(issueEvidence["dismissed"] == .bool(true))
        let issueValue = try #require(issueEvidence["value"])
        let issue = try await registry.decode(issueValue, as: BorderDriftIssue.self, in: token)
        #expect(issue.id == selectedIssueID)
        #expect(issue.nearestRegion == .california)
        #expect(issue.distanceMeters > 0 && issue.distanceMeters <= drift.thresholdMeters)
        #expect(issue.day.regions == [.other])
        let retainedBeforeRepeat = try await registry.objectReferences(in: token)
        #expect(try await invoke(
            .init(rawValue: "where.investigation.replay"),
            arguments: replayArguments,
        ) == replay)
        #expect(try await registry.objectReferences(in: token) == retainedBeforeRepeat)

        let scannerEvidenceAfter = try await invoke(
            .init(rawValue: "where.scanner.state"),
            arguments: .object([:]),
        )
        #expect(scannerEvidenceAfter == scannerEvidenceBefore)
        #expect(await services.resolution.diagnosticState == scannerBefore)
        #expect(try await services.reports.yearReport(for: drift.day.year) == reportBefore)
        #expect(try await services.reports.manualDays(inYear: drift.day.year) == manualDaysBefore)
        #expect(try await drift.store.dismissedIssueIDs() == [selectedIssueID])
        #expect(try await drift.store.samples(in: DateInterval(
            start: drift.sample.timestamp.addingTimeInterval(-1),
            end: drift.sample.timestamp.addingTimeInterval(1),
        )) == [drift.sample])

        let parentReference = try #require(capture["$reference"])
            .decode(PortholeObjectReference.self)
        for evidence in [inputEvidence, attributionEvidence, issueValue] {
            let reference = try #require(evidence["$reference"])
                .decode(PortholeObjectReference.self)
            #expect(reference.scope == token)
            #expect(reference != parentReference)
        }
        try await registry.release(parentReference)
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.decode(inputEvidence, as: DataIssueInput.self, in: token)
        }
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.decode(attributionEvidence, as: RegionAttributor.self, in: token)
        }
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.decode(issueValue, as: BorderDriftIssue.self, in: token)
        }
        await registry.invalidate(token)
    }
}
