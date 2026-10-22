import Foundation
import SnapshotReviewCore
@_spi(Testing) @testable import SnapshotReviewUI

actor ReviewTestStorage: ReviewWorkspaceStorage {
    var scanned: [SnapshotSuite] = []
    var saved: ReviewDocument?
    var shouldFail = false
    var holdSave = false
    var saveStarted = false
    var continuation: CheckedContinuation<Void, Never>?
    func scan(root _: URL) -> [SnapshotSuite] {
        scanned
    }

    func setScan(_ suites: [SnapshotSuite]) {
        scanned = suites
    }

    func failWrites() {
        shouldFail = true
    }

    func suspendSave() {
        holdSave = true
    }

    func releaseSave() {
        continuation?.resume(); continuation = nil
    }

    func save(
        _ document: ReviewDocument,
        suite _: URL,
        expected _: Data?,
        image _: SnapshotImage,
    ) async throws -> ReviewFile {
        saveStarted = true
        if holdSave { await withCheckedContinuation { continuation = $0 } }
        if shouldFail { throw ReviewError.externalChange }
        saved = document
        return try .init(document: document, bytes: ReviewJSON.encode(document))
    }
}

@MainActor enum ReviewBrowserTestSupport {
    static func model(storage: ReviewTestStorage) throws -> ReviewBrowserModel {
        let model = ReviewBrowserModel(storage: storage, preferences: UserDefaults())
        let root = URL(fileURLWithPath: "/workspace")
        let suite = root.appendingPathComponent("__Snapshots__/ScreenTests")
        var images: [SnapshotImage] = []
        for frame in ["iPhone", "iPad"] {
            for variant in [SnapshotVariant.light, .dark] {
                let path =
                    try SnapshotPath("test.Loaded_\(frame)_\(variant.colorScheme.rawValue).png")
                images.append(SnapshotImage(
                    id: .init(suite: suite, path: path),
                    metadata: .init(
                        path: path,
                        testName: "test",
                        caseName: "Loaded",
                        configurationIdentifier: frame,
                        frame: frame,
                        configurationName: nil,
                        layoutTraits: nil,
                        variant: variant,
                    ),
                    content: .success(.init(
                        fingerprint: path.value,
                        modifiedAt: Date(timeIntervalSince1970: 1000),
                        pixels: .init(width: 40, height: 60),
                    )),
                ))
            }
        }
        model.installFixture(
            root: root,
            suites: [.init(
                id: suite,
                name: "ScreenTests",
                images: images,
                reviews: .success(.init(document: .init(images: []), bytes: nil)),
                manifestError: nil,
            )],
        )
        model.select(.group(model.caseID(images[0])))
        return model
    }
}
