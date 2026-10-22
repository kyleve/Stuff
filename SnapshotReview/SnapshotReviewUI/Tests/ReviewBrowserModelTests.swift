import Foundation
import SnapshotReviewCore
@testable import SnapshotReviewUI
import Testing

@MainActor struct ReviewBrowserModelTests {
    @Test func reloadingAnEditorPreservesDraftAndExternalAnnotations() async throws {
        let storage = ReviewTestStorage()
        let model = try ReviewBrowserTestSupport.model(storage: storage)
        let image = try #require(model.visibleImages.first)
        model.select(.image(image.id))
        model.beginAnnotation(point: .init(x: 0.5, y: 0.5))
        model.draft?.annotation.text = "My unsaved feedback"
        let draft = try #require(model.draft)
        var suites = model.suites
        var content = try image.content.get()
        content.fingerprint = "new image"
        suites[0].images[0].content = .success(content)
        let externalNote = ReviewAnnotation(
            text: "Another reviewer’s note",
            status: .note,
            point: nil,
            fingerprint: "new image",
            date: Date(),
        )
        let document = ReviewDocument(images: [.init(
            path: image.id.path,
            reviewed: nil,
            annotations: [externalNote],
        )])
        suites[0].reviews = try .success(.init(
            document: document,
            bytes: ReviewJSON.encode(document),
        ))
        await storage.setScan(suites)
        let reloaded = await model.reloadDraft(draft)
        #expect(reloaded.annotation.text == draft.annotation.text)
        #expect(reloaded.annotation.fingerprint == draft.annotation.fingerprint)
        #expect(try reloaded.image.content.get().fingerprint == "new image")
        await model.saveDraft()
        #expect(model.draft == nil)
        #expect(model.review(image)?.annotations.count == 2)
        #expect(model.review(image)?.annotations.contains(externalNote) == true)
    }

    @Test func reviewActionsWaitForTheSelectedRevisionToLoad() throws {
        let model = try ReviewBrowserTestSupport.model(storage: ReviewTestStorage())
        let image = try #require(model.visibleImages.first)
        model.select(.image(image.id))
        #expect(!model.canReviewDisplayedImage)
        model.displayedImage = .init(imageID: image.id, fingerprint: "older")
        #expect(!model.canReviewDisplayedImage)
        model.displayedImage = try .init(
            imageID: image.id,
            fingerprint: image.content.get().fingerprint,
        )
        #expect(model.canReviewDisplayedImage)
        model.appearance = .dark
        #expect(!model.canReviewDisplayedImage)
        let dark = try #require(model.selectedImage)
        model.displayedImage = try .init(
            imageID: dark.id,
            fingerprint: dark.content.get().fingerprint,
        )
        #expect(model.canReviewDisplayedImage)
    }

    @Test func defaultsToBothLightDevicesAndPairsSingleImage() throws {
        let model = try ReviewBrowserTestSupport.model(storage: ReviewTestStorage())
        #expect(model.visibleImages.count == 2)
        #expect(model.visibleImages.allSatisfy { $0.metadata?.variant == .light })
        let image = try #require(model.visibleImages.first)
        model.select(.image(image.id))
        model.appearance = .dark
        #expect(model.selectedImage?.metadata?.frame == image.metadata?.frame)
        #expect(model.selectedImage?.metadata?.variant == .dark)
        model.appearance = .other
        #expect(model.selectedImage == nil)
        #expect(model.isSingleImage)
    }

    @Test func failedSaveRetainsDraftAndDoesNotAdvance() async throws {
        let storage = ReviewTestStorage()
        await storage.failWrites()
        let model = try ReviewBrowserTestSupport.model(storage: storage)
        model.startReview()
        let first = try #require(model.selectedImage)
        model.beginAnnotation(point: .init(x: 0.4, y: 0.7))
        model.draft?.annotation.text = "Fix clipping"
        await model.saveDraft()
        #expect(model.draft?.annotation.text == "Fix clipping")
        #expect(model.error != nil)
        await model.reviewAndNext()
        #expect(model.queue?.index == 0)
        #expect(model.needsReview(first))
    }

    @Test func advancesOnlyAfterSaveCompletesAndLeavesDarkPending() async throws {
        let storage = ReviewTestStorage()
        await storage.suspendSave()
        let model = try ReviewBrowserTestSupport.model(storage: storage)
        model.startReview()
        let first = try #require(model.selectedImage)
        let operation = Task { await model.reviewAndNext() }
        while await !storage.saveStarted {
            await Task.yield()
        }
        #expect(model.queue?.index == 0)
        #expect(model.isBusy)
        await storage.releaseSave()
        await operation.value
        #expect(model.queue?.index == 1)
        #expect(model.queue?.reviewed.count == 1)
        #expect(!model.needsReview(first))
        let darkImages = model.images.filter { $0.metadata?.variant == .dark }
        #expect(darkImages.allSatisfy(model.needsReview))
    }

    @Test func todoResolutionDoesNotMarkImageReviewed() async throws {
        let model = try ReviewBrowserTestSupport.model(storage: ReviewTestStorage())
        let image = try #require(model.visibleImages.first)
        let note = ReviewAnnotation(
            text: "Fix title",
            status: .resolved,
            point: nil,
            fingerprint: "older",
            date: Date(),
        )
        #expect(await model.updateAnnotation(note, image: image))
        #expect(model.needsReview(image))
        #expect(model.review(image)?.openTodoCount == 0)
        #expect(model.review(image)?.annotations.first?.fingerprint == "older")
    }

    @Test func switchingCasesLeavesReviewQueue() throws {
        let model = try ReviewBrowserTestSupport.model(storage: ReviewTestStorage())
        model.startReview()
        let group = try #require(model.selectedCase)
        model.select(.group(group))
        #expect(model.queue == nil)
    }

    @Test(.timeLimit(.minutes(1))) func undoAndRedoPersistReviewChanges() async throws {
        let model = try ReviewBrowserTestSupport.model(storage: ReviewTestStorage())
        let image = try #require(model.visibleImages.first)
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        manager.beginUndoGrouping()
        #expect(await model.markReviewed(image, reviewed: true))
        manager.endUndoGrouping()
        #expect(manager.canUndo)
        manager.undo()
        while model.review(image)?.reviewed != nil {
            await Task.yield()
        }
        #expect(manager.canRedo)
        manager.redo()
        while model.review(image)?.reviewed == nil {
            await Task.yield()
        }
        #expect(!model.needsReview(image))
    }
}
