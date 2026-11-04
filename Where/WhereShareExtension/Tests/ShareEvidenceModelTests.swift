import Foundation
import Testing
import UniformTypeIdentifiers
import WhereCore

@MainActor
struct ShareEvidenceModelTests {
    @Test func everyAttachmentAndMetadataAreQueuedBeforeCompletingTheShare() async throws {
        let queue = ShareEvidenceQueueSpy()
        let pdf = Data("%PDF-1.7 shared receipt".utf8)
        let text = Data("Reservation details".utf8)
        let item = NSExtensionItem()
        item.attachments = [provider(pdf, as: .pdf), provider(text, as: .plainText)]
        let instant = Date(timeIntervalSince1970: 100)
        let model = ShareEvidenceModel(items: [item], makeQueue: { queue }, now: { instant })
        #expect(!model.hasPreparedDraft)
        #expect(await model.save() == false)
        await model.loadAttachments()
        model.kind = .document
        model.note = "Trip evidence"
        #expect(await model.save())
        let draft = try #require(await queue.attempts.first)
        #expect(draft.items.map(\.blob) == [pdf, text])
        #expect(draft.items.map(\.evidence.capturedAt) == [instant, instant])
        #expect(draft.items.map(\.evidence.note) == ["Trip evidence", "Trip evidence"])
        #expect(Set(draft.items.map(\.evidence.id)).count == 2)
        #expect(await queue.pendingDraftIDs() == [draft.id])
    }

    @Test func uncertainSaveRetriesTheSamePreparedIdentityAndBytes() async {
        let queue = ShareEvidenceQueueSpy()
        await queue.failAfterSaving(true)
        let model = ShareEvidenceModel(items: [], makeQueue: { queue })
        await model.loadAttachments()
        model.note = "Original note"
        #expect(await model.save() == false)
        #expect(model.isShowingSaveError)
        guard case let .failed(error) = model.phase
        else { Issue.record("Expected save failure"); return }
        #expect(error is ShareEvidenceQueueSpy.UncertainSave)
        #expect(model.hasPreparedDraft)
        model.isShowingSaveError = false
        // The UI locks these fields after preparation. Even a stale binding cannot change a retry.
        model.note = "Late edit"
        await queue.failAfterSaving(false)
        #expect(await model.save())
        let attempts = await queue.attempts
        #expect(attempts.count == 2)
        #expect(attempts[0] == attempts[1])
        #expect(attempts[0].items.count == 1)
        #expect(attempts[0].items[0].blob == nil)
        #expect(attempts[0].items[0].evidence.note == "Original note")
        #expect(await queue.pendingDraftIDs().count == 1)
    }

    @Test func aSecondSaveCannotCompleteWhileTheFirstEnqueueIsHeld() async {
        let queue = ShareEvidenceQueueSpy()
        await queue.holdEnqueue()
        let model = ShareEvidenceModel(items: [], makeQueue: { queue })
        await model.loadAttachments()
        let saving = Task { await model.save() }
        await queue.waitUntilStarted()
        #expect(model.isSaving)
        #expect(await model.save() == false)
        #expect(await queue.pendingDraftIDs().isEmpty)
        await queue.release()
        #expect(await saving.value)
        #expect(await queue.attempts.count == 1)
    }

    private func provider(_ data: Data, as type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) {
            completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
