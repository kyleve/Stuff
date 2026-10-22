import Foundation
import SnapshotReviewCore

struct ReviewCase: Identifiable, Hashable, Codable {
    struct ID: Hashable, Codable {
        var suite: URL
        var testName: String?
        var caseName: String?
    }

    var id: ID
    var label: String {
        id.caseName.map { "\(id.testName ?? "") · \($0)" } ?? "Ungrouped"
    }
}

enum ReviewSelection: Hashable {
    case group(ReviewCase.ID)
    case image(SnapshotImage.ID)
}

enum ReviewFilter: String, Codable, CaseIterable {
    case all = "All"
    case needsReview = "Needs review"
    case openTodos = "Open todos"
}

/// Local navigation preferences, encoded together so restoration stays coherent.
struct ReviewSession: Codable {
    var bookmark: Data
    var root: URL
    struct Location: Codable {
        var group: ReviewCase.ID
        var image: SnapshotPath?
    }

    var location: Location?
    var appearance: SnapshotVariant.Appearance
    var other: SnapshotVariant?
    var filter: ReviewFilter
    var search: String
}

struct ReviewQueue {
    let images: [SnapshotImage.ID]
    var index: Int = 0
    var reviewed: Set<SnapshotImage.ID> = []
    var current: SnapshotImage.ID? {
        images.indices.contains(index) ? images[index] : nil
    }
}

struct AnnotationDraft: Identifiable {
    let id = UUID()
    var image: SnapshotImage
    var annotation: ReviewAnnotation
}
