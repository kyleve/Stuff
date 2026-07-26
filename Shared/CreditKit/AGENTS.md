# CreditKit — Module Shape

Attribution for the third-party work a Stuff app is built with, as data the app
can render. See [`README.md`](README.md) for the API and the generation flow;
the repo-wide build, format, and convention rules are in the root
[`AGENTS.md`](../../AGENTS.md).

## Scope & dependencies

- **May import:** Foundation, `PeriscopeCore` (logging only).
- **Must not import:** any app or feature module (`WhereCore`, `WhereUI`, …),
  or any UI framework. CreditKit is a leaf that anything may depend on; a
  dependency edge pointing *out* of it would defeat the reason it exists.
- **Wired in:** `Package.swift` (`CreditKit` product, consumed by `WhereUI`)
  and `Project.swift` (`CreditKitTests`, in the `Stuff-iOS-Tests` scheme).

## Layering

`SoftwareCredit` is the value; `CreditCatalog` is the bundled list. Nothing
else in the module holds state, and neither type knows how it is presented —
grouping, labeling, and translation belong to the consuming UI.

## Invariants

- **The manifest and the notices are generated, never hand-edited.**
  `Sources/Resources/credits.json` and `Sources/Resources/Licenses/*.txt` are
  written by `Tools/generate-credits.rb`; editing them by hand puts them at odds
  with `Package.resolved` and `.agents/external-skills.json` and the next run
  silently reverts it. Re-run the script and commit the result.
- **Adding a dependency anywhere means re-running the script.** The generator
  reads `.product(name:package:)` out of the root `Package.swift`, so a package
  linked by *any* module is picked up — but only when someone runs it.
  `CreditCatalogTests` pins the expected names and is what fails if that is
  skipped, so update the test in the same change as a deliberate dependency
  change.
- **`Kind` is load-bearing, not decoration.** `.developmentTool` credits are not
  in the shipping binary. A UI that renders both kinds in one undifferentiated
  list would misrepresent the app, so the distinction must survive into the
  presentation.
- **Only packages that are actually linked are `.library` credits.** Packages
  resolved for tooling alone (BumperBowling, and swift-syntax beneath it) are
  excluded by construction, because the generator keys off `.product(…)` usage
  rather than the `dependencies:` list.

## Testing

`CreditKitTests` covers the bundled catalog end to end: that the manifest
decodes, that the expected libraries and tools are present, and that every
credit resolves a non-empty notice. Shared fixtures live in
`CreditKitTestSupport.swift`. The missing-notice path is deliberately untested —
it trips an `assertionFailure`, which traps the process rather than raising a
catchable issue.
