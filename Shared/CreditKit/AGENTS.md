# CreditKit — Module Shape

Tools and types for working out what an app owes attribution to, and for
shipping that answer inside the app. See [`README.md`](README.md) for the API
and the report format; the repo-wide build, format, and convention rules are in
the root [`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- **May import:** Foundation. Nothing else — not even logging.
- **Must not import:** any app or feature module (`WhereCore`, `WhereUI`, …), or
  any UI framework. CreditKit is a leaf that anything may depend on; an edge
  pointing *out* of it would defeat the reason it exists.
- **Wired in:** `Package.swift` (`CreditKit` product, consumed by `WhereCore`
  and `WhereUI`) and `Project.swift` (`CreditKitTests`, in the
  `Stuff-iOS-Tests` scheme).

## Layering

`SoftwareCredit` and `LicenseNotice` are the values; `AttributionManifest` is a
decoded report plus the two ways to get one (`decode(from:)`,
`load(from:resource:)`). Nothing holds state, nothing is a singleton, and
nothing knows how a report is presented — grouping, labeling, and translation
belong to the consuming UI.

`Tools/generate-attribution.rb` is the other half of the module and is the only
thing that writes a report.

## Invariants

- **CreditKit ships no credits and no notices.** A report describes one app's
  dependency graph, so it belongs in that app's resources — for Where, in
  `Where/Where/Resources/attribution.json`. If a license file or a `credits.json`
  ever reappears under `Sources/`, the module has drifted back into being one
  app's data.
- **Nothing here may name a real dependency.** `CreditKitTests` covers the
  format and the API with fixtures only; asserting that some package is credited
  is the *app's* test to write, because only the app knows what it links. See
  `AppAttributionTests` in `Where/Where/Tests/`.
- **Failure is thrown, never logged or defaulted.** The module has no logger by
  design, and a missing report is not inherently an error — only the app knows
  which of its bundles are expected to carry one. Returning an empty manifest
  instead of throwing would render as "nothing to credit", which is the one
  wrong answer.
- **`Kind` is load-bearing, not decoration.** `.developmentTool` credits are not
  in the shipping binary. A UI that renders both kinds in one undifferentiated
  list would misrepresent the app, so the distinction must survive into the
  presentation. Its raw values are a wire format the generator writes; renaming
  a case silently invalidates every committed report. The generator validates
  each source's `kind` against them before it does any work, so a config typo
  fails there rather than as a decode fault inside the app.
- **Credit names are unique across a report.** `SoftwareCredit` is `Identifiable`
  by `name`, so a duplicate hands a SwiftUI `ForEach` two rows with one id — and
  a library's name is its repo basename, so two orgs publishing the same repo
  name is all it takes. The generator enforces this (case-insensitively) over the
  assembled report, since that is the only place holding every credit at once.
- **Notices are read at the pinned revision.** Not the default branch — upstream
  edits a notice between releases, and shipping HEAD's text would attribute
  terms that don't govern the code in the binary.
- **The generator keys off `.product(name:package:)`, not the `dependencies:`
  list.** That is what keeps a package resolved for tooling alone (BumperBowling,
  and swift-syntax beneath it) out of a report by construction.

## Testing

`CreditKitTests` covers the manifest as a format and an API: decoding the exact
JSON the generator writes, rejecting a malformed report or an unknown `kind`,
round-tripping, filtering by kind, and `load` throwing for a bundle with no
report. Shared fixtures live in `CreditKitTestSupport.swift`, and
`SampleReport.json` is a literal rather than an encoder round-trip so a Swift-side
change that breaks the wire format fails a test.
