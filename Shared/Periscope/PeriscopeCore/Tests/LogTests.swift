import Foundation
import PeriscopeCore
import Testing

struct LogTests {
    let recorder = RecordingRecorder()

    @Test func rootScopeIsNamedAfterTheEventType() {
        let root = Log<AppLogs>(recorder: recorder)
        #expect(root.primaryScope.name == "AppLogs")
        #expect(root.primaryScope.parentID == nil)
        #expect(recorder.definedScopes.contains(root.primaryScope))
    }

    @Test func derivingAnEventTypeCreatesATypedChildScope() {
        let root = Log<AppLogs>(recorder: recorder)
        let photos = root(PhotoLogs.self)
        #expect(photos.primaryScope.name == "PhotoLogs")
        #expect(photos.primaryScope.parentID == root.primaryScope.id)
        #expect(recorder.definedScopes.contains(photos.primaryScope))
    }

    @Test func derivingForAnIdentifierCreatesAKeyedChildScope() {
        let root = Log<AppLogs>(recorder: recorder)
        let photos = root(PhotoLogs.self)
        let album = photos(for: "album-1")
        #expect(album.primaryScope.name == "album-1")
        #expect(album.primaryScope.parentID == photos.primaryScope.id)
    }

    @Test func samePathDerivedTwiceIsTheSameScope() {
        let a = Log<AppLogs>(recorder: recorder)(PhotoLogs.self)(for: "album-1")
        let b = Log<AppLogs>(recorder: recorder)(PhotoLogs.self)(for: "album-1")
        #expect(a.primaryScope == b.primaryScope)
    }

    @Test func emittingRecordsTheEventWithAllScopes() throws {
        let root = Log<AppLogs>(recorder: recorder)
        let photos = root(PhotoLogs.self)

        photos { PhotoLogs(photoID: "p1") }

        let record = try #require(recorder.records.first)
        #expect(record.scopes == photos.scopes.map(\.id))
        #expect(record.message == "photo p1")
        #expect(record.level == .notice)
    }

    @Test func linkingMergesScopesKeepingLeftPrimary() {
        let model = Log<PhotoLogs>(recorder: recorder)(for: "photo-9")
        let ui = Log<AppLogs>(recorder: recorder)(for: "detail-screen")

        let joined = model + ui

        #expect(joined.primaryScope == model.primaryScope)
        #expect(joined.scopes == model.scopes + ui.scopes)

        joined { PhotoLogs(photoID: "p9") }
        #expect(recorder.records.last?.scopes == (model.scopes + ui.scopes).map(\.id))
    }

    @Test func linkingCollapsesDuplicateScopes() {
        let model = Log<PhotoLogs>(recorder: recorder)
        let joined = model + model
        #expect(joined.scopes == model.scopes)
    }

    @Test func linkedFormMatchesTheOperator() {
        let model = Log<PhotoLogs>(recorder: recorder)
        let ui = Log<AppLogs>(recorder: recorder)
        #expect(model.linked(with: ui).scopes == (model + ui).scopes)
    }

    @Test func derivingFromALinkedLogKeepsLinkedScopes() {
        let model = Log<PhotoLogs>(recorder: recorder)
        let ui = Log<AppLogs>(recorder: recorder)
        let child = (model + ui)(for: "photo-9")
        #expect(child.primaryScope.parentID == model.primaryScope.id)
        #expect(child.scopes.contains(ui.primaryScope))
    }

    @Test func typedDeriveAndEmitWorksAsOneExpression() throws {
        let root = Log<AppLogs>(recorder: recorder)

        root(PhotoLogs.self) { PhotoLogs(photoID: "p1") }

        let record = try #require(recorder.records.first)
        #expect(record.message == "photo p1")
        #expect(record.scopes == root(PhotoLogs.self).scopes.map(\.id))
    }

    @Test func keyedDeriveAndEmitWorksAsOneExpression() throws {
        let photos = Log<AppLogs>(recorder: recorder)(PhotoLogs.self)

        photos(for: "album-1") { PhotoLogs(photoID: "p2") }

        let record = try #require(recorder.records.first)
        #expect(record.message == "photo p2")
        #expect(record.scopes == photos(for: "album-1").scopes.map(\.id))
    }

    @Test func retypingKeepsTheContextWithoutDerivingAChild() {
        let photos = Log<AppLogs>(recorder: recorder)(PhotoLogs.self)
            .tagged(LogTagKey("payment-id"), "pay_1")

        let retyped = photos.retyped(to: Message.self)

        #expect(retyped.scopes == photos.scopes)
        #expect(retyped.tags == photos.tags)

        retyped.info("still in photos")
        #expect(recorder.records.last?.scopes == photos.scopes.map(\.id))
    }

    @Test func attachmentsRideAlongWithEvents() {
        let log = Log<PhotoLogs>(recorder: recorder)
        let attachment = LogAttachment(
            name: "thumbnail",
            contentType: .png,
            data: Data([9]),
        )

        log(attachments: [attachment]) { PhotoLogs(photoID: "p1") }
        log.error("boom", attachments: [attachment])
        log.info("bare")

        let records = recorder.records
        #expect(records[0].attachments == [attachment])
        #expect(records[1].attachments == [attachment])
        #expect(records[2].attachments.isEmpty)
    }

    @Test func taggedContextsStampEveryEvent() {
        let root = Log<AppLogs>(recorder: recorder)
        let tagged = root.tagged(LogTagKey("payment-id"), "pay_123")

        tagged.info("charged")
        tagged { AppLogs() }

        #expect(recorder.records.count == 2)
        #expect(recorder.records.allSatisfy { $0.tags == [LogTag(
            key: LogTagKey("payment-id"),
            value: "pay_123",
        )] })

        root.info("untagged")
        #expect(recorder.records.last?.tags.isEmpty == true)
    }

    @Test func tagsFlowDownDerivations() {
        let root = Log<AppLogs>(recorder: recorder).tagged(LogTagKey("payment-id"), "pay_123")
        let child = root(PhotoLogs.self)(for: "album-1")

        child.info("deep")
        #expect(recorder.records.last?.tags == [LogTag(
            key: LogTagKey("payment-id"),
            value: "pay_123",
        )])
    }

    @Test func laterTagsOverrideEarlierValuesForTheSameKey() {
        let key = LogTagKey("payment-id")
        let log = Log<AppLogs>(recorder: recorder).tagged(key, "old").tagged(key, "new")
        #expect(log.tags == [LogTag(key: key, value: "new")])
    }

    @Test func emitsCaptureTheirCallSite() {
        let log = Log<AppLogs>(recorder: recorder)
        log.info("freeform")
        log { AppLogs() }

        for record in recorder.records {
            #expect(record.callSite?.function == "emitsCaptureTheirCallSite()")
            #expect(record.callSite?.fileID.hasSuffix("LogTests.swift") == true)
        }
        #expect(recorder.records.count == 2)
    }

    @Test func taggedAcceptsTypedValues() {
        let log = Log<AppLogs>(recorder: recorder)
            .tagged(LogTagKey("payment-id"), "pay_1")
            .tagged(LogTagKey("retry"), 3)
            .tagged(LogTagKey("ratio"), 0.5)
            .tagged(LogTagKey("cached"), true)

        #expect(log.tags[LogTagKey("payment-id")] == .string("pay_1"))
        #expect(log.tags[LogTagKey("retry")] == .int(3))
        #expect(log.tags[LogTagKey("ratio")] == .double(0.5))
        #expect(log.tags[LogTagKey("cached")] == .bool(true))
    }

    @Test func linkingMergesTagsWithTheLeftSideWinning() {
        let key = LogTagKey("payment-id")
        let model = Log<PhotoLogs>(recorder: recorder)
            .tagged(key, "model-side")
            .tagged(LogTagKey("model-only"), "m")
        let ui = Log<AppLogs>(recorder: recorder)
            .tagged(key, "ui-side")
            .tagged(LogTagKey("ui-only"), "u")

        let joined = model + ui

        // Arrays keep insertion order: the model's tags first (left side
        // is primary), then the ui's non-conflicting keys.
        #expect(joined.tags == [
            LogTag(key: key, value: "model-side"),
            LogTag(key: LogTagKey("model-only"), value: "m"),
            LogTag(key: LogTagKey("ui-only"), value: "u"),
        ])
    }

    @Test func freeformConveniencesEmitMessageEventsAtEachLevel() {
        let log = Log<AppLogs>(recorder: recorder)

        log.debug("d")
        log.info("i")
        log.notice("n")
        log.warning("w")
        log.error("e")
        log.fault("f")
        log.log(LogLevel(name: "audit", severity: 450), "a")

        let records = recorder.records
        #expect(records.count == 7)
        #expect(records.allSatisfy { $0.eventName == Message.eventName })
        #expect(records.map(\.message) == ["d", "i", "n", "w", "e", "f", "a"])
        #expect(records.map(\.level) == [
            .debug,
            .info,
            .notice,
            .warning,
            .error,
            .fault,
            LogLevel(name: "audit", severity: 450),
        ])
    }
}
