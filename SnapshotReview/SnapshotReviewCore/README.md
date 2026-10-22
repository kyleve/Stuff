# SnapshotReviewCore

SnapshotReviewCore defines the review file format and reads local SnapshotKit references. It has no UIKit, SwiftUI, or comparison-engine dependency.

## Use

Create one `ReviewWorkspaceStore` at the app root. Call `scan(root:)` with a folder that the caller can access.
The actor returns suites with per-image metadata, content fingerprints, dimensions, timestamps, and review files.
A broken image or review file remains an explicit failure in its suite. A folder traversal failure throws.

```swift
let store = ReviewWorkspaceStore()
let suites = try await store.scan(root: selectedFolder)
```

The caller owns security-scoped access for the lifetime of those URLs.
The store performs file reads and serialized saves on its actor.

## Review storage

`ReviewDocument` stores one `ImageReview` per suite-relative `SnapshotPath`.
An image review contains an optional reviewed revision and an ordered list of annotations.
A revision stores the review date, SHA-256 fingerprint, and image modification date at review.
A matching fingerprint means reviewed, regardless of modification time or open todos.

`ReviewAnnotation.Status` is `note`, `open`, or `resolved`. A missing point means the whole image.
Points use normalized coordinates from the top-left corner. An annotation retains the fingerprint of its source image.
The UI compares fingerprints to identify outdated points.

Use `ReviewWorkspaceStorage.save(_:suite:expected:image:)` to save. Pass the bytes returned by the prior read and the displayed image revision.
The store rejects a changed image or externally edited review file. It never replaces an unsupported or malformed document.
`ReviewFileStore` coordinates and atomically replaces JSON files. Missing-image records remain intact.

## Capture metadata

`SnapshotManifest` describes exact test/case names, configuration labels, and appearance axes for each reference path.
SnapshotKitTesting calls `ReviewFileStore.updateManifest(_:suite:)` after a successful comparison or recording.
The operation merges entries and skips identical writes. Filtered runs retain entries from other tests.
The browser discovers actual PNG files independently, so stale manifest entries do not create images.

Both JSON files use format version 1, sorted keys, stable relative paths, and ISO 8601 timestamps.
`ReviewJSON` centralizes their encoding. `ReviewMarkdown` exports open todos, including missing-image and outdated-image labels.

## Tests

Run `./test SnapshotReviewCoreTests`. Tests cover unsafe paths, discovery, LFS pointers, freshness, external edits, and exports.
