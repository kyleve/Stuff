import SwiftData
import Testing
@testable import WhereCore

/// Transaction-author filtering behind the external-only store signal.
struct StoreHistoryClassifierTests {
    @Test func excludesLocalAuthorAndIncludesAnotherAuthor() throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let localAuthor = "where-tests-local"
        let classifier = StoreHistoryClassifier(
            container: container,
            localAuthor: localAuthor,
        )
        let initialToken = try classifier.checkpoint()

        let localContext = ModelContext(container)
        localContext.author = localAuthor
        let localDay = SDManualDay()
        localDay.dayKey = "2026-03-15"
        localContext.insert(localDay)
        try localContext.save()

        let local = try classifier.classify(after: initialToken)
        #expect(local.containsExternalTransaction == false)

        let otherContext = ModelContext(container)
        otherContext.author = "where-tests-other-process"
        let otherDay = SDManualDay()
        otherDay.dayKey = "2026-03-16"
        otherContext.insert(otherDay)
        try otherContext.save()

        let external = try classifier.classify(after: local.latestToken)
        #expect(external.containsExternalTransaction)
    }
}
