# WhereShareExtension – Module Shape

The **Where** share extension is a Share-sheet action. It writes shared content
(PDFs, images, Wallet passes, emails, links) into the app's store as a new
`Evidence`. See [`README.md`](README.md) for the data path and design.

This file complements the root [`AGENTS.md`](../../AGENTS.md) and the feature
[`Where/AGENTS.md`](../AGENTS.md). Read those first.

## Scope & dependencies

- **Tuist app-extension target** ([`Project.swift`](../../Project.swift), with
  an audience-specific bundle ID and App Group), depending on **WhereCore**,
  **WhereUI**, **PeriscopeCore**, and **SFSafeSymbols**. Embedded by the **Where**
  app. Logs via the `WhereLog` facade (typed `ShareExtensionLog` events); as a
  separate process its
  `Periscope.shared` is OSLog-only (no store).
- Presentation reuses WhereUI's public `EvidenceKind.symbol`/`displayName`.
  Only extension chrome lives in this target's catalog. Reference it through its
  generated `LocalizedStringResource` symbols.
- No test bundle. The store write contract is covered from **WhereCore** store
  tests. This target's own compose/save model (`ShareEvidenceModel`) is
  untested. Tracked in [`Where/TODOs.md`](../TODOs.md).

## Invariants

- **Writes directly through `SwiftDataStore.perform { write(evidence:blob:) }`,
  not `WhereServices`/`DayJournal`.** A short-lived share process must not spin
  up the GPS ingestor, notifiers, or widget publisher; the store commit's
  persistent-history ping is what the app reconciles from later.
- **Opens `.localOnly` storage, never CloudKit.** The extension holds only the
  App Group entitlement (no iCloud), so it must not initialize the CloudKit
  mirror; the app's container syncs the shared store's history. Resolve that
  group through `WhereShareBuildEnvironment` and inject it into the store.
- **`NSExtensionPrincipalClass` is `$(PRODUCT_MODULE_NAME).ShareViewController`**
  — keep the class name and Info.plist in sync. Save/cancel bridge to
  `extensionContext` completion; the root view has no `@Environment(\.dismiss)`.
- **A share with no loadable bytes still composes** a metadata-only note rather
  than failing — but a provider that *reported* a reason for the empty result
  logs it. `SharedItemLoader` reduces each callback to one `LoadedValue`, so
  "nothing, and here's why" can't be flattened into the same silence as "nothing
  was offered". The load is also the extension's one span (attachment count and
  size are what the wait scales with).

## Testing

No hosted bundle. Exercise `EvidenceContentType.classify` and the store write
contract in **WhereCore**. Preview the compose sheet via the in-file `#Preview`
(DEBUG). It uses an `.inMemory` model with no shared-container access.
