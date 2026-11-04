# WhereShareExtension – Module Shape

The **Where** share extension is a Share-sheet action. It saves shared content
(PDFs, images, Wallet passes, emails, links) as pending drafts for the next admitted app session.
See [`README.md`](README.md) for the data path and design.

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
- `WhereShareExtensionTests` compiles the actual compose model, loader, and view in StuffTestHost.
  `WhereShareExtensionSnapshotTests` captures the compose form in the shared image scheme.
  Keep the OS principal controller and audience adapter outside these hosted source lists.

## Invariants

- **Never open history or CloudKit.** The extension cannot verify shared compatibility.
  Save metadata and bytes through `SharedEvidenceDraftQueuing`; the app imports through admitted services.
  Resolve the App Group through `WhereShareBuildEnvironment` and inject the queue factory.
- Preserve a prepared draft's identity and bytes through uncertain saves. Disable edits after preparation and retry that same draft.
  Complete the extension request only after enqueue succeeds. Keep enqueue failures visible and preserve the original error.
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

Core covers classification, draft publication, and receipt-based import. `WhereSharedEvidenceModelTests` covers the verified app-session handoff.
The extension's hosted tests cover real item-provider loading, attachment composition, uncertain save retries, and concurrent Save.
Keep compose snapshots with `ShareEvidenceView` through `SnapshotProviding`; use the shared date-picker wrapper for deterministic capture.
The principal controller's system completion callbacks still require platform integration coverage.
