import Foundation
import SnapshotReviewCore
import Testing

struct ReviewDocumentTests {
    @Test func contentIdentityIsIndependentOfTodosAndTime() throws {
        let path = try SnapshotPath("image.png")
        let date = Date(timeIntervalSince1970: 1000)
        let todo = ReviewAnnotation(
            text: "Fix the title",
            status: .open,
            point: .init(x: 0.2, y: 0.7),
            fingerprint: "old",
            date: date,
        )
        let review = ImageReview(
            path: path,
            reviewed: .init(date: date, fingerprint: "current", modifiedAt: date),
            annotations: [todo],
        )
        #expect(!review.needsReview(fingerprint: "current"))
        #expect(review.needsReview(fingerprint: "changed"))
        #expect(review.openTodoCount == 1)
        let document = ReviewDocument(images: [review])
        #expect(try ReviewJSON
            .decode(ReviewDocument.self, from: ReviewJSON.encode(document)) == document)
    }

    @Test func rejectsDuplicateAndInvalidCoordinates() throws {
        let path = try SnapshotPath("image.png")
        var annotation = ReviewAnnotation(
            text: "Point",
            status: .note,
            point: .init(x: 1.1, y: 0),
            fingerprint: "x",
            date: Date(),
        )
        let invalid = ReviewDocument(images: [.init(
            path: path,
            reviewed: nil,
            annotations: [annotation],
        )])
        #expect(throws: ReviewError.self) { try invalid.validate() }
        annotation.point = .init(x: 1, y: 0)
        let duplicate = ReviewDocument(images: [.init(
            path: path,
            reviewed: nil,
            annotations: [annotation, annotation],
        )])
        #expect(throws: ReviewError.self) { try duplicate.validate() }
    }

    @Test func unsupportedVersionFails() {
        var document = ReviewDocument(images: [])
        document.version = 99
        #expect(throws: ReviewError.self) { try document.validate() }
    }
}
