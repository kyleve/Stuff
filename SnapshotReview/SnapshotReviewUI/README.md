# SnapshotReviewUI

SnapshotReviewUI provides the SwiftUI browser and the UIKit image canvas for the Snapshot Review app.
It depends on SnapshotReviewCore, Broadway, SnapshotKit, and SFSafeSymbols. It does not link the capture engine.

## Composition

Create `ReviewBrowserModel(storage:preferences:)` once and pass it to `ReviewBrowserView(model:)`.
Attach `ReviewCommands(model:)` to the app scene for keyboard actions.
The model uses an injected `ReviewWorkspaceStorage`; tests use a conforming in-memory store.
The root view supplies the Broadway context and connects the system undo manager.

The left pane contains case navigation and image details. The right pane contains a grid or single-image canvas.
The Light/Dark/Other selection preserves the case and device. Missing counterparts have an explicit unavailable state.
A stable review queue captures the currently visible pending images. It advances only after a successful save.

## Image rendering

`ReviewImageLoader` hashes loaded bytes against the inspected revision before decoding them.
Its actor caches bounded thumbnails. The selected full-resolution image belongs to the visible canvas.
Review and annotation actions remain disabled until its loaded fingerprint matches the selected revision.
`ReviewCanvas` uses one scroll view and image coordinate system for zoom and pin placement.
`ReviewCanvasGeometry` preserves proportional scroll progress across image sizes and rejects points outside image bounds.

`ReviewSessionStore` owns scoped workspace access and one encoded navigation preference.
Catalyst bookmarks request security scope; the app target supplies user-selected read/write and bookmark entitlements.
The model preserves annotation drafts on write failures. Undo and Redo use the same guarded persistence path.
Refresh clears undo history after loading external state.

This developer tool uses English literal labels. System controls keep native appearances.
Authored dimensions and pin colors belong to `ReviewStylesheet`.

## Tests and previews

Run `./test SnapshotReviewUITests` for model, geometry, and stylesheet checks.
Run `./test SnapshotReviewUISnapshotTests` for the browser’s image fixtures.
The shared `StuffSnapshotTests` scheme owns those references.
The view’s `SnapshotProviding` matrix also supplies Xcode previews.
