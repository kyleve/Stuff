import Foundation
import Observation
import SnapshotReviewCore
import UIKit

/// Owns one scoped workspace and serializes user intents across asynchronous file operations.
@MainActor @Observable
public final class ReviewBrowserModel {
    enum State {
        case closed
        case loading
        case open(URL, [SnapshotSuite])
        case failed(any Error)
    }

    private(set) var state: State = .closed
    var selection: ReviewSelection?
    var appearance: SnapshotVariant.Appearance = .light {
        didSet {
            if oldValue != appearance { queue = nil; placement = nil; saveSession() }
        }
    }

    var other: SnapshotVariant? {
        didSet {
            if oldValue != other { queue = nil; placement = nil; saveSession() }
        }
    }

    var filter: ReviewFilter = .all {
        didSet { if oldValue != filter { queue = nil; saveSession() } }
    }

    var search = "" {
        didSet { if oldValue != search { queue = nil; saveSession() } }
    }

    var error: (any Error)?
    var draft: AnnotationDraft?
    struct DisplayedImage: Equatable {
        var imageID: SnapshotImage.ID
        var fingerprint: String
    }

    var displayedImage: DisplayedImage?
    var canReviewDisplayedImage: Bool {
        guard let image = selectedImage,
              case let .success(content) = image.content else { return false }
        return displayedImage == .init(imageID: image.id, fingerprint: content.fingerprint)
    }

    var selectedAnnotation: ReviewAnnotation.ID?
    enum Placement { case newPoint, move(ReviewAnnotation.ID) }
    var placement: Placement?
    var queue: ReviewQueue?
    var isImporting = false
    var isBusy = false
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private let storage: any ReviewWorkspaceStorage
    @ObservationIgnored private let sessionStore: ReviewSessionStore

    public init(storage: any ReviewWorkspaceStorage, preferences: UserDefaults) {
        self.storage = storage
        sessionStore = ReviewSessionStore(preferences: preferences)
    }

    #if DEBUG
        /// Installs an in-memory scan result for synchronous previews and intent tests.
        @_spi(Testing) public func installFixture(root: URL, suites: [SnapshotSuite]) {
            state = .open(root, suites)
        }
    #endif

    var root: URL? {
        if case let .open(root, _) = state { root } else { nil }
    }

    var suites: [SnapshotSuite] {
        if case let .open(_, suites) = state { suites } else { [] }
    }

    var images: [SnapshotImage] {
        suites.flatMap(\.images)
    }

    var cases: [ReviewCase] {
        Set(images.filter(matchesFilter).map { ReviewCase(id: caseID($0)) }).sorted {
            ($0.id.suite.path, $0.label) < ($1.id.suite.path, $1.label)
        }
    }

    func caseID(_ image: SnapshotImage) -> ReviewCase.ID {
        .init(
            suite: image.id.suite,
            testName: image.metadata?.testName,
            caseName: image.metadata?.caseName,
            referenceGroup: image.metadata?.referenceGroup,
        )
    }

    var selectedCase: ReviewCase.ID? {
        switch selection {
            case let .group(group): group
            case let .image(imageID): images.first { $0.id == imageID }.map(caseID)
            case nil: nil
        }
    }

    var caseImages: [SnapshotImage] {
        images.filter { caseID($0) == selectedCase }
    }

    var otherVariants: [SnapshotVariant] {
        Set(caseImages.compactMap(\.metadata?.variant).filter { $0.appearance == .other })
            .sorted { $0.label < $1.label }
    }

    var effectiveOther: SnapshotVariant? {
        other ?? otherVariants.first
    }

    var visibleImages: [SnapshotImage] {
        caseImages.filter { matchesVariant($0) && matchesFilter($0) }
    }

    var selectedImage: SnapshotImage? {
        guard case let .image(imageID) = selection,
              let anchor = images.first(where: { $0.id == imageID }) else { return nil }
        guard let metadata = anchor.metadata else { return anchor }
        return caseImages.first {
            guard let candidate = $0.metadata else { return false }
            return candidate.frame == metadata.frame && candidate.configurationName == metadata
                .configurationName && candidate.layoutTraits == metadata
                .layoutTraits && matchesVariant($0)
        }
    }

    var isSingleImage: Bool {
        if case .image = selection { true } else { false }
    }

    func matchesVariant(_ image: SnapshotImage) -> Bool {
        guard let variant = image.metadata?.variant else { return true }
        switch appearance {
            case .light: return variant == .light
            case .dark: return variant == .dark
            case .other: return variant == effectiveOther
        }
    }

    func matchesFilter(_ image: SnapshotImage) -> Bool {
        let terms = [
            image.id.path.value,
            image.id.suite.lastPathComponent,
            image.metadata?.caseName ?? "",
            image.metadata?.testName ?? "",
        ].joined(separator: " ")
        guard search.isEmpty || terms.localizedCaseInsensitiveContains(search) else { return false }
        switch filter {
            case .all: return true
            case .needsReview: return needsReview(image)
            case .openTodos: return review(image)?.openTodoCount ?? 0 > 0
        }
    }

    func review(_ image: SnapshotImage) -> ImageReview? {
        guard let suite = suites.first(where: { $0.id == image.id.suite }),
              case let .success(file) = suite.reviews else { return nil }
        return file.document.review(for: image.id.path)
    }

    func needsReview(_ image: SnapshotImage) -> Bool {
        guard case let .success(content) = image.content,
              let review = review(image) else { return true }
        return review.needsReview(fingerprint: content.fingerprint)
    }

    func countLabel(_ group: ReviewCase.ID) -> String {
        let members = images.filter { caseID($0) == group }
        return "\(members.filter(needsReview).count) pending · \(members.reduce(0) { $0 + (review($1)?.openTodoCount ?? 0) }) todos"
    }

    func select(_ value: ReviewSelection?) {
        selection = value
        if selectedImage?.id != displayedImage?.imageID { displayedImage = nil }
        queue = nil
        placement = nil
        selectedAnnotation = nil
        saveSession()
    }

    func cycleOther(_ offset: Int) {
        guard !otherVariants.isEmpty else { return }
        let index = effectiveOther.flatMap { otherVariants.firstIndex(of: $0) } ?? 0
        other = otherVariants[(index + offset + otherVariants.count) % otherVariants.count]
        appearance = .other
    }

    public func open(_ url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let newBookmark = try sessionStore.makeBookmark(url)
            let contents = try await storage.scan(root: url)
            sessionStore.adopt(url, bookmark: newBookmark, accessed: accessed)
            state = .open(url, contents)
            error = nil
            selection = nil
            appearance = .light
            other = nil
            filter = .all
            search = ""
            queue = nil
            undoManager?.removeAllActions()
            select(cases.first.map { .group($0.id) })
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            self.error = error
            if root == nil { state = .failed(error) }
        }
    }

    public func restore() async {
        guard case .closed = state else { return }
        do {
            guard let session = try sessionStore.load() else { return }
            let url = try sessionStore.resolve(session)
            await open(url)
            guard root == url else { return }
            appearance = session.appearance
            other = session.other
            filter = session.filter
            search = session.search
            if let location = session.location {
                let group = ReviewCase.ID(
                    suite: url
                        .appendingPathComponent(String(location.group.suite.path
                                .dropFirst(session.root.path.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
                    testName: location.group.testName,
                    caseName: location.group.caseName,
                    referenceGroup: location.group.referenceGroup,
                )
                select(location.image
                    .map { .image(.init(suite: group.suite, path: $0)) } ?? .group(group))
            }
        } catch { self.error = error; isImporting = true }
    }

    func refresh() async {
        guard !isBusy, let root else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let contents = try await storage.scan(root: root)
            state = .open(root, contents)
            error = nil
            undoManager?.removeAllActions()
        } catch { self.error = error }
    }

    private func saveSession() {
        guard let root else { return }
        let path: SnapshotPath? = if case let .image(imageID) = selection { imageID.path }
        else { nil }
        let location = selectedCase.map { ReviewSession.Location(group: $0, image: path) }
        do {
            try sessionStore.save(
                root: root,
                location: location,
                appearance: appearance,
                other: other,
                filter: filter,
                search: search,
            )
        } catch { self.error = error }
    }

    func beginAnnotation(point: ReviewAnnotation.Point?) {
        guard let image = selectedImage, case let .success(content) = image.content else { return }
        draft = AnnotationDraft(
            image: image,
            annotation: .init(
                text: "",
                status: .open,
                point: point,
                fingerprint: content.fingerprint,
                date: Date(),
            ),
        )
        placement = nil
    }

    func place(_ point: ReviewAnnotation.Point) async {
        guard let placement, let image = selectedImage else { return }
        switch placement {
            case .newPoint: beginAnnotation(point: point)
            case let .move(annotationID):
                guard var annotation = review(image)?.annotations
                    .first(where: { $0.id == annotationID }),
                    case let .success(content) = image.content else { return }
                annotation.point = point
                annotation.fingerprint = content.fingerprint
                annotation.editedAt = Date()
                if await updateAnnotation(annotation, image: image) { self.placement = nil }
        }
    }

    func reloadDraft(_ currentDraft: AnnotationDraft) async -> AnnotationDraft {
        await refresh()
        var updated = currentDraft
        if let image = images
            .first(where: { $0.id == currentDraft.image.id }) { updated.image = image }
        draft = updated
        return updated
    }

    func saveDraft() async {
        guard let draft else { return }
        var annotation = draft.annotation
        annotation.editedAt = Date()
        if await updateAnnotation(annotation, image: draft.image) { self.draft = nil }
    }

    @discardableResult func updateAnnotation(
        _ annotation: ReviewAnnotation,
        image: SnapshotImage,
    ) async -> Bool {
        guard var review = review(image) else { return false }
        review.annotations.removeAll { $0.id == annotation.id }
        review.annotations.append(annotation)
        return await commit(review, image: image, action: "Edit Annotation")
    }

    func deleteAnnotation(_ annotation: ReviewAnnotation, image: SnapshotImage) async {
        guard var review = review(image) else { return }
        review.annotations.removeAll { $0.id == annotation.id }
        _ = await commit(review, image: image, action: "Delete Annotation")
    }

    func markReviewed(_ image: SnapshotImage, reviewed: Bool) async -> Bool {
        guard var review = review(image),
              case let .success(content) = image.content else { return false }
        review.reviewed = reviewed ? .init(
            date: Date(),
            fingerprint: content.fingerprint,
            modifiedAt: content.modifiedAt,
        ) : nil
        return await commit(
            review,
            image: image,
            action: reviewed ? "Mark Reviewed" : "Mark Unreviewed",
        )
    }

    private func commit(_ review: ImageReview, image: SnapshotImage, action: String) async -> Bool {
        guard !isBusy, let index = suites.firstIndex(where: { $0.id == image.id.suite }),
              case let .success(file) = suites[index].reviews else { return false }
        var document = file.document
        document.set(review)
        guard document != file.document else { return true }
        if await write(document, image: image) {
            registerUndo(document: file.document, inverse: document, image: image, action: action)
            return true
        }
        return false
    }

    private func write(_ document: ReviewDocument, image: SnapshotImage) async -> Bool {
        guard !isBusy, let root, let index = suites.firstIndex(where: { $0.id == image.id.suite }),
              case let .success(file) = suites[index].reviews else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let saved = try await storage.save(
                document,
                suite: image.id.suite,
                expected: file.bytes,
                image: image,
            )
            var updated = suites
            updated[index].reviews = .success(saved)
            state = .open(root, updated)
            error = nil
            return true
        } catch { self.error = error; return false }
    }

    private func registerUndo(
        document: ReviewDocument,
        inverse: ReviewDocument,
        image: SnapshotImage,
        action: String,
    ) {
        undoManager?.registerUndo(withTarget: self) { model in
            model.registerUndo(document: inverse, inverse: document, image: image, action: action)
            Task { @MainActor in
                if await model
                    .write(document, image: image) ==
                    false { model.undoManager?.removeAllActions() }
            }
        }
        undoManager?.setActionName(action)
    }

    func startReview() {
        let pending = visibleImages.filter(needsReview).map(\.id)
        queue = ReviewQueue(images: pending)
        revealQueueImage()
    }

    func reviewAndNext() async {
        guard let image = selectedImage else { return }
        if queue == nil {
            var pending = visibleImages.filter(needsReview).map(\.id)
            if !pending.contains(image.id) { pending.insert(image.id, at: 0) }
            var newQueue = ReviewQueue(images: pending)
            newQueue.index = pending.firstIndex(of: image.id) ?? 0
            queue = newQueue
        }
        guard queue?.current == image.id else { return }
        if await markReviewed(image, reviewed: true) {
            queue?.reviewed.insert(image.id)
            advance(1)
        }
    }

    func advance(_ offset: Int) {
        guard var queue else { return }
        queue.index = min(queue.images.count, max(0, queue.index + offset))
        self.queue = queue
        revealQueueImage()
    }

    private func revealQueueImage() {
        guard let imageID = queue?.current,
              let image = images.first(where: { $0.id == imageID }) else { return }
        let activeQueue = queue
        if let variant = image.metadata?.variant {
            appearance = variant.appearance
            if variant.appearance == .other { other = variant }
        }
        select(.image(imageID))
        queue = activeQueue
    }

    func copyTodos(entireWorkspace: Bool) {
        guard let root else { return }
        do {
            UIPasteboard.general.string = try ReviewMarkdown.export(
                suites: suites,
                root: root,
                imageIDs: entireWorkspace ? nil : Set(caseImages.map(\.id)),
            )
        } catch { self.error = error }
    }
}
