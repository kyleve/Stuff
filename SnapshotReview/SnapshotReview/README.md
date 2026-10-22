# Snapshot Review

Snapshot Review opens a repository or a folder under `__Snapshots__`. Select a case to browse its regular light captures.
Use Light, Dark, or Other to inspect another configuration. The grid includes every available device.

Select an image to zoom, add a whole-image note, or place a point. Todos have open and resolved states.
Mark Reviewed records the current PNG fingerprint and timestamps. Changed PNG contents require another review.

Review and Next saves the review before advancing. Skip leaves review status unchanged. Back returns to the prior queue entry.
The queue covers the visible filtered case. Sidebar counts include hidden variants.

Use Copy Todos to copy Markdown for the selected case or workspace. JSON remains the source of truth.
Undo and Redo cover annotation and review changes during the session. Refresh clears history after reading external state.

## Build and launch

Run `./ide --no-open`. Then build the Mac app:

```sh
mise exec -- tuist build SnapshotReview -- -destination 'platform=macOS,variant=Mac Catalyst'
```

The shared scheme supports Mac Catalyst and iOS. The companion is designed for a desktop window.

## Files

Each suite owns `snapshot-manifest.json` and `snapshot-reviews.json`. Both use format version 1.
The capture runner writes exact case and configuration metadata after successful captures and comparisons.
Images without metadata appear under Ungrouped. Run their snapshot tests to populate the manifest.

Review writes check external file contents before atomic replacement. A conflict retains the editor draft.
Reload the files before applying the draft again. Malformed and unsupported files remain untouched.
Missing-image records remain in the review file. Renames do not transfer review status automatically.

Point coordinates are normalized from the image’s top-left corner. Changed images retain points with an outdated indicator.
Confirm or move those points after inspection. Mark Reviewed does not confirm them.

The app restores the last folder with a scoped bookmark. It also restores selection, appearance, search, and filters.
A missing permission requires another folder selection. Large canvases follow SnapshotKit’s 32,000-pixel and 100-million-pixel limits.
Review actions wait until the selected image revision has loaded. Refresh after changing files outside the app.

## Development

Core provides `SnapshotManifest`, `ReviewDocument`, `ReviewWorkspaceStorage`, and `ReviewWorkspaceStore`.
The app injects a store into `ReviewBrowserModel`, then presents `ReviewBrowserView` and `ReviewCommands`.

Run the Core and UI bundles with `./test`. UI snapshots use the shared StuffSnapshotTests scheme.
See [ROADMAP.md](ROADMAP.md) for product direction and [TODOs.md](../TODOs.md) for deferred work.

## Keyboard controls

| Action | Shortcut |
| --- | --- |
| Open folder | Command-O |
| Light / Dark / Other | Command-1 / Command-2 / Command-3 |
| Previous / next Other configuration | Command-Option-Left / Right |
| Start review | Command-Shift-R |
| Review and next | Command-Return |
| Back / skip | Command-Left / Right |
| Refresh | Command-R |
| Undo / redo | Command-Z / Command-Shift-Z |
