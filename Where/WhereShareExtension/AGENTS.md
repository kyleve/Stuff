# WhereShareExtension – Module Shape

The **Where** share extension is a Share-sheet action. It writes shared content
(PDFs, images, Wallet passes, emails, links) into the app's store as a new
`Evidence`. See [`README.md`](README.md) for the data path and design.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift),
  bundle ID `com.stuff.where.share`), depending on **WhereCore**, **WhereUI**,
  and **PeriscopeCore**. Embedded by the **Where** app. Shares the
  `group.com.stuff.where` App Group entitlement. Logs via the `WhereLog` facade
  (typed `ShareExtensionLog` events). As a separate process its
  `Periscope.shared` is OSLog-only (no store).
- Presentation reuses WhereUI's public `EvidenceKind.symbolName`/`displayName`.
  Only extension chrome lives in this target's catalog. Reference it through its
  generated `LocalizedStringResource` symbols.
- No test bundle. The store write contract is covered from **WhereCore** store
  tests. This target's own compose/save model (`ShareEvidenceModel`) is
  untested. Tracked in [`Where/TODOs.md`](../TODOs.md).

## Invariants

- **Write directly through `SwiftDataStore.perform { write(evidence:blob:) }`.
  Do not use `WhereServices`/`DayJournal`.** A short-lived share process must
  not spin up the GPS ingestor, notifiers, or widget publisher. The store
  commit's persistent-history ping is what the app reconciles from later.
- **Open `.localOnly` storage. Never use CloudKit.** The extension holds only
  the App Group entitlement (no iCloud). It must not initialize the CloudKit
  mirror. The app's container syncs the shared store's history.
- **`NSExtensionPrincipalClass` is `$(PRODUCT_MODULE_NAME).ShareViewController`.**
  Keep the class name and Info.plist in sync. Save/cancel bridge to
  `extensionContext` completion. The root view has no `@Environment(\.dismiss)`.
- **If a share has no loadable bytes, still compose** a metadata-only note
  rather than failing. If a provider *reported* a reason for the empty result,
  log it. `SharedItemLoader` reduces each callback to one `LoadedValue`. Then
  "nothing, and here's why" can't be flattened into the same silence as "nothing
  was offered". The load is also the extension's one span. Attachment count and
  size are what the wait scales with.

## Testing

No hosted bundle. Exercise `EvidenceContentType.classify` and the store write
contract in **WhereCore**. Preview the compose sheet via the in-file `#Preview`
(DEBUG). It uses an `.inMemory` model with no shared-container access.
