# CreditKit — Module Shape

CreditKit provides tools and types for working out what an app owes attribution to, and for shipping that answer inside the app. See [`README.md`](README.md) for the API and the report format. Repo-wide build, format, and convention rules are in the root [`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- **May import:** Foundation. Nothing else — not even logging. CreditKit is a leaf that anything may depend on.
- **Must not import:** any app or feature module, or any UI framework.
- **Wired in:** `Package.swift` (`CreditKit` product) and `Project.swift` (`CreditKitTests`, in the `Stuff-iOS-Tests` scheme). Presentation belongs to the consuming UI. `Tools/generate-attribution.rb` is the only thing that writes a report.

## Invariants

- **CreditKit ships no credits and no notices.** A report describes one app's dependency graph. It lives in that app's resources (for Where, `Where/Where/Resources/attribution.json`). Never put it under `Sources/` here.
- **Nothing here may name a real dependency.** `CreditKitTests` uses fixtures only. Asserting that some package is credited is the app's test (`AppAttributionTests` in `Where/Where/Tests/`).
- **Throw on failure. Never log or default.** An empty manifest renders as "nothing to credit". That is the one wrong answer. Only the app knows which of its bundles must carry a report.
- **`Kind` is load-bearing.** A UI must keep `.developmentTool` and library credits visually distinct. Raw values are a wire format. Renaming a case invalidates every committed report. The generator validates each source's `kind` up front so a config typo fails there, not as a decode fault in-app.
- **Credit names are unique across a report.** The generator enforces this case-insensitively. `SoftwareCredit` is `Identifiable` by `name`. A library's name is its repo basename.
- **Read notices at the pinned revision.** Never read the default branch. HEAD's text may not govern the code in the binary.
- **The generator keys off `.product(name:package:)`, not `dependencies:`.** That keeps tooling-only packages (BumperBowling, swift-syntax) out of a report by construction.
- **`kind` is derived from reachability, not declared.** `shippedFrom` names the app's root package targets. Anything inside that closure is a `library`. Any other linked package is a `developmentTool`. Linking is not shipping. `shippedFrom` is the only hand-set part for SPM packages. **`agentSkills` and `developmentTools` declare `kind` in config** — both are development tools in Where today.

## Testing

`CreditKitTests` covers the manifest as a format and an API. It decodes the exact JSON the generator writes. It rejects malformed reports and unknown `kind`s. It round-trips, filters, and makes `load` throw for a bundle with no report. Shared fixtures live in `CreditKitTestSupport.swift`. Its `SampleReport.json` (a string constant on the `SampleReport` enum, not a fixture file) is a literal rather than an encoder round-trip. Then a Swift-side change that breaks the wire format fails a test.
