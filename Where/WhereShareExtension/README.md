# WhereShareExtension

The **Where** share extension: a Share-sheet action that saves shared content —
a boarding pass, a PDF receipt, a screenshot, a forwarded reservation email, a
Wallet ticket — into Where as a new piece of [`Evidence`](../WhereCore/Sources/Evidence/Evidence.swift).

Pick "Where" from any app's Share sheet, confirm the kind / date / note in the
compose sheet, and tap **Save**. The attachment bytes and metadata are written
straight into the shared App Group SwiftData store the app reads.

## How it works

```
Host app Share sheet
    └─▶ ShareViewController (principal class)
            └─▶ SharedItemLoader           (extract bytes from NSItemProviders)
            └─▶ ShareEvidenceView + Model  (SwiftUI compose sheet)
                    └─▶ SwiftDataStore.perform { write(evidence:blob:) }
                            └─▶ App Group store (group.com.stuff.where)
```

- **`SharedItemLoader`** takes the first `NSItemProvider` that yields bytes,
  preferring the most preview-friendly representation it registered: PDF →
  image → concrete file (`.pkpass`, `.eml`, …) → text → URL (kept as its
  string). A share with nothing loadable still composes as a metadata-only note.
- **`ShareEvidenceModel`** holds the editable fields, classifies the attachment
  with [`EvidenceContentType.classify`](../WhereCore/Sources/Evidence/EvidenceContentType+Classify.swift),
  and persists a new `Evidence`.
- **`ShareEvidenceView`** is the compose form; kind names/symbols reuse
  WhereUI's public `EvidenceKind` presentation helpers so they read identically
  to the in-app "Add evidence" sheet. Extension-only chrome resolves through
  `ShareStrings` from this target's own catalog.

## Why write to the store directly

The extension opens the store and writes through
`SwiftDataStore.perform { … }` rather than going through
`WhereServices`/`DayJournal`. Those assemble a live GPS ingestor, notification
reconcilers, and widget publishing — machinery with no place in a short-lived
share process. The commit pings persistent history, so the app reconciles
badges/widgets and (in production) mirrors the new row to CloudKit the next time
it opens.

The extension opens `.localOnly` storage on purpose: it must not initialize
CloudKit (it holds only the App Group entitlement, not iCloud), and the app's
CloudKit container picks the write up from the shared store's history.

## Installation

`WhereShareExtension` is a Tuist app-extension target in
[`Project.swift`](../../Project.swift) (bundle ID `com.stuff.where.share`),
depending on **WhereCore**, **WhereUI**, and **LogKit**. The main **Where** app
embeds the extension and shares the `group.com.stuff.where` App Group
entitlement so both processes open the same SwiftData store.

## Limitations

- **No test bundle.** The build-and-write path is exercised indirectly by
  **WhereCore** store tests and the **WhereUI** compose model; the loader and
  view controller are thin glue over system APIs.
- **No live in-app refresh in DEBUG.** A running debug app (`.localOnly`, no
  remote-change observer) picks up an extension write on its next launch/fetch,
  not instantly.
