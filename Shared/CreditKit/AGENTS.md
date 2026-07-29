# CreditKit — Module Shape

Tools and types for working out what an app owes attribution to, and for
shipping that answer inside the app. See [`README.md`](README.md) for the API
and the report format; the repo-wide build, format, and convention rules are in
the root [`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- **May import:** Foundation. Nothing else — not even logging. CreditKit is a
  leaf that anything may depend on.
- **Must not import:** any app or feature module, or any UI framework.
- **Wired in:** `Package.swift` (`CreditKit` product) and `Project.swift`
  (`CreditKitTests`, in the `Stuff-iOS-Tests` scheme). Presentation belongs to
  the consuming UI; `Tools/generate-attribution.rb` is the only thing that
  writes a report.

## Invariants

- **CreditKit ships no credits and no notices.** A report describes one app's
  dependency graph and lives in that app's resources (for Where,
  `Where/Where/Resources/attribution.json`) — never under `Sources/` here.
- **Nothing here may name a real dependency.** `CreditKitTests` uses fixtures
  only; asserting that some package is credited is the app's test
  (`AppAttributionTests` in `Where/Where/Tests/`).
- **Failure is thrown, never logged or defaulted** — an empty manifest would
  render as "nothing to credit", the one wrong answer. Only the app knows
  which of its bundles should carry a report.
- **`Kind` is load-bearing** — a UI must keep `.developmentTool` and library
  credits visually distinct. Its raw values are a wire format; renaming a case
  invalidates every committed report. The generator validates each source's
  `kind` up front so a config typo fails there, not as a decode fault in-app.
- **Credit names are unique across a report** (enforced case-insensitively by
  the generator) — `SoftwareCredit` is `Identifiable` by `name`, and a
  library's name is its repo basename.
- **Notices are read at the pinned revision**, never the default branch —
  HEAD's text may not govern the code in the binary.
- **The generator keys off `.product(name:package:)`, not `dependencies:`** —
  that keeps tooling-only packages (BumperBowling, swift-syntax) out of a
  report by construction.
- **`kind` is derived from reachability, not declared.** `shippedFrom` names
  the app's root package targets; anything inside that closure is a `library`,
  any other linked package a `developmentTool` — linking is not shipping.
  `shippedFrom` is the only hand-set part.

## Testing

`CreditKitTests` covers the manifest as a format and an API: decoding the
exact JSON the generator writes, rejecting malformed reports and unknown
`kind`s, round-tripping, filtering, and `load` throwing for a bundle with no
report. Shared fixtures live in `CreditKitTestSupport.swift`; its
`SampleReport.json` (a string constant on the `SampleReport` enum, not a
fixture file) is a literal rather than an encoder round-trip so a Swift-side
change that breaks the wire format fails a test.
