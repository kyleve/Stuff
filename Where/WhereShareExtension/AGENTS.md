# WhereShareExtension – Module Shape

The **Where** share extension: a Share-sheet action that writes shared content
(PDFs, images, Wallet passes, emails, links) into the app's store as a new
`Evidence`. See [`README.md`](README.md) for the data path and design.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  bundle ID `com.stuff.where.share`), depending on **WhereCore**, **WhereUI**,
  and **PeriscopeCore**. Embedded by the **Where** app; shares the
  `group.com.stuff.where` App Group entitlement. Logs via the `WhereLog` facade
  (typed `ShareExtensionLog` events); as a separate process its
  `Periscope.shared` is OSLog-only (no store).
- Presentation reuses WhereUI's public `EvidenceKind.symbolName`/`displayName`;
  only extension chrome lives in this target's `ShareStrings` + catalog.
- No test bundle; the write path is covered from **WhereCore** store tests and
  the **WhereUI** compose model.

## Invariants

- **Writes directly through `SwiftDataStore.perform { write(evidence:blob:) }`,
  not `WhereServices`/`DayJournal`.** A short-lived share process must not spin
  up the GPS ingestor, notifiers, or widget publisher; the store commit's
  persistent-history ping is what the app reconciles from later.
- **Opens `.localOnly` storage, never CloudKit.** The extension holds only the
  App Group entitlement (no iCloud), so it must not initialize the CloudKit
  mirror; the app's container syncs the shared store's history.
- **`NSExtensionPrincipalClass` is `$(PRODUCT_MODULE_NAME).ShareViewController`**
  — keep the class name and Info.plist in sync. Save/cancel bridge to
  `extensionContext` completion; the root view has no `@Environment(.dismiss)`.
- **A share with no loadable bytes still composes** a metadata-only note rather
  than failing.

## Testing

No hosted bundle. Exercise `EvidenceContentType.classify` and the store write
contract in **WhereCore**; preview the compose sheet via the in-file `#Preview`
(DEBUG), which uses an `.inMemory` model with no shared-container access.
