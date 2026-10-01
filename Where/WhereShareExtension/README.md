# WhereShareExtension

The **Where** share extension.
It is a Share-sheet action that saves shared content — a boarding pass, a PDF receipt, a screenshot, a forwarded reservation email, a Wallet ticket — into Where as a new piece of [`Evidence`](../WhereCore/Sources/Evidence/Evidence.swift).

Pick "Where" from any app's Share sheet, confirm the kind / date / note in the compose sheet, and tap **Save**.
The attachment bytes and metadata are written straight into the shared App Group SwiftData store the app reads.

## How it works

```
Host app Share sheet
    └─▶ ShareViewController (principal class)
            └─▶ SharedItemLoader           (extract bytes from NSItemProviders)
            └─▶ ShareEvidenceView + Model  (SwiftUI compose sheet)
                    └─▶ SwiftDataStore.perform { write(evidence:blob:) }
                            └─▶ audience-selected App Group store
```

- **`SharedItemLoader`** takes one attachment per `NSItemProvider` that yields bytes (so a multi-item share — the activation rule allows up to 20 — keeps them all), preferring the most preview-friendly representation each registered: PDF → image → concrete file (`.pkpass`, `.eml`, …) → text → URL (kept as its string). A share with nothing loadable still composes as a metadata-only note, with whatever reason the provider gave logged as a warning. The whole load is one Periscope span, since it is what the wait between tapping Share and seeing the compose form is spent on.
- **`ShareEvidenceModel`** holds the editable fields, classifies each attachment with [`EvidenceContentType.classify`](../WhereCore/Sources/Evidence/EvidenceContentType+Classify.swift), and persists one `Evidence` per attachment (all sharing the form's kind/date/note) in a single transaction.
- **`ShareEvidenceView`** is the compose form.
  Kind names/symbols reuse WhereUI's public `EvidenceKind` presentation helpers so they read identically to the in-app "Add evidence" sheet.
  Extension-only chrome resolves through this target's own catalog via its generated symbols (`String(localized: .shareTitle)`).

## Why write to the store directly

The extension opens the store and writes through `SwiftDataStore.perform { … }` rather than going through `WhereServices`/`DayJournal`.
Those assemble a live GPS ingestor, notification reconcilers, and widget publishing — machinery with no place in a short-lived share process.
The commit enters persistent history. The app’s container-scoped `HistoryObserverRemoteChangeSource` classifies external authors and forwards the change to its reconciliation streams; Beta and App Store also mirror the shared store through CloudKit.

The extension opens `.localOnly` storage on purpose.
It must not initialize CloudKit (it holds only the App Group entitlement, not iCloud).
The app's CloudKit container picks the write up from the shared store's history.

## Installation

`WhereShareExtension` is a Tuist app-extension target in
[`Project.swift`](../../Project.swift), with a bundle ID and App Group selected
by the Where audience (Development is isolated; Beta and App Store share the
production family),
depending on **WhereCore**, **WhereUI**, and **PeriscopeCore**. The main **Where** app
embeds the extension with the same audience-selected App Group entitlement so
both processes open the same SwiftData store.

## Limitations

- **No test bundle.** WhereCore tests cover the store-write contract and production history observation against temporary on-disk stores. This extension’s compose model, item loader, and view-controller glue remain untested; see [`../TODOs.md`](../TODOs.md).
- **Refresh depends on app execution.** Both local-only and CloudKit app stores observe external commits through SwiftData history. Services reconcile when their observer can run, and scene-scoped reports subscribe while active and refresh on activation. A suspended app cannot repaint; the source does not deliberately defer every external write until the next foreground. Live cross-process and CloudKit delivery still require device validation.

## Compatibility

Evidence saves use the same guarded transaction as the app. An unsupported data
requirement or verification failure rejects the write before mutation. The compose
sheet shows localized guidance to open Where for an update or retry.
