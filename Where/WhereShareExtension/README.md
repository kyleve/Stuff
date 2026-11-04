# WhereShareExtension

The Where Share-sheet action saves boarding passes, receipts, images, emails, tickets, and links as pending evidence.
Choose Where from another app's Share sheet, edit the kind, date, and note, then tap **Save**.
Where imports the saved items the next time an app session can access its history.

## How it works

1. `ShareViewController` receives the shared items.
2. `SharedItemLoader` extracts available bytes from each item provider.
3. `ShareEvidenceModel` prepares one immutable `SharedEvidenceDraft`, with one evidence record per attachment.
4. `FileSharedEvidenceDraftQueue` publishes the complete draft in the audience's App Group.
5. The admitted app session imports the draft through `SharedEvidenceImporter`.

The loader prefers PDF, image, concrete file, text, then URL representations.
A share without loadable bytes still composes a metadata-only note. Provider failures are logged.
Each attachment keeps its own content type and bytes. All items use the form's kind, date, and note.

An uncertain save retries the same draft identity and contents. The form stays locked after preparation to preserve that contract.
The extension completes its request only after enqueue succeeds. Failure keeps the compose sheet open for retry.
The view reuses WhereUI's evidence names and symbols. Extension chrome uses this target's generated localization symbols.

## History admission and recovery

The extension has no iCloud entitlement, so it cannot verify shared-data compatibility.
It never opens SwiftData or starts application services.
Pending drafts retain their attachment bytes while app access is blocked.

The app saves evidence and a delivery receipt in one guarded transaction, then acknowledges the draft.
A crash after commit can retry without duplicating evidence or restoring evidence deleted afterward.
Receipts survive Reset and Replace. The pending directory is excluded from system backup; delivery receipts are omitted from user archives.
Import failures leave the draft available and show a retry action in the app.

## Installation

`Project.swift` defines the audience-specific extension target, bundle ID, and App Group.
Development has an isolated group. Beta and App Store share the production group.
The extension uses WhereCore and WhereUI APIs and logs typed events through Periscope.
The app embeds the matching extension and shares its draft directory.

## Validation limits

WhereCore tests cover draft publication, attachment preservation, transaction rollback, permit revocation, reset races, and receipt recovery.
WhereUI tests cover blocked launch, successful admission, foreground import, and retry after failed acknowledgement.
The hosted extension tests compile the production compose sources and use real item providers with scripted queue failures.
They cover every attachment, metadata-only notes, uncertain retries, and overlapping Save actions.
The image bundle captures the native form in light, dark, and accessibility sizes.
The OS principal controller and system completion callbacks are outside these hosted tests.
The in-file preview uses an injected memory queue. Import requires app execution; saving a draft cannot wake a suspended app.
