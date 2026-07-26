# CreditKit

Attribution for the third-party work a Stuff app is built with — the libraries
it links and the tools it is developed with — as data the app can render.

CreditKit exists so attribution has one home instead of living wherever a
dependency happened to be introduced. It is a Shared module at the bottom of the
graph, so any module's dependency can be credited without inverting the
dependency that introduced it.

## Install

Add the `CreditKit` product to a target in the root `Package.swift`. It depends
only on `PeriscopeCore`, for logging.

## Quick start

```swift
import CreditKit

for credit in CreditCatalog.shared.credits(ofKind: .library) {
    print(credit.name, credit.version, credit.licenseName)
    print(credit.licenseText() ?? "notice unavailable")
}
```

The Where app renders this in Settings → About: `WhereUI`'s `AboutSettingsView`
shows one section per kind, and `LicenseView` pushes the full notice.

## Public API

- **`SoftwareCredit`** — one credited work: `name`, `kind`, `version`,
  `homepageURL`, `licenseName`, and `licenseText()` for the verbatim notice.
- **`SoftwareCredit.Kind`** — `.library` (compiled into the binary) or
  `.developmentTool` (used to build the project, absent from the shipped app).
- **`CreditCatalog`** — `shared` for the bundled catalog, `credits` for
  everything in manifest order, and `credits(ofKind:)` to filter.

## How it works

`CreditCatalog.shared` decodes a bundled `credits.json`, and each credit's
notice is a vendored `Resources/Licenses/<name>.txt`. Both are **generated**:

```bash
ruby Shared/CreditKit/Tools/generate-credits.rb
```

The script derives the list from what the repository already declares, so the
manifest can't drift from reality:

| Kind | Derived from | Notice fetched from |
|------|--------------|---------------------|
| `.library` | packages a target links via `.product(name:package:)` in `Package.swift`, pinned by `Package.resolved` | the project's GitHub repo, at the pinned revision |
| `.developmentTool` | `.agents/external-skills.json` — the agent skills `./sync-agents` vendors | the skill's GitHub repo, at the pinned ref |

Deriving rather than hand-maintaining is the point: a package linked by *any*
module is credited the next time the script runs, so no module has to remember
to vend a credit. It needs network and an authenticated `gh`, and it is
idempotent — re-run it after changing a dependency or running
`./sync-agents --update`, and commit the result.

Notices are read at the **pinned revision**, not the default branch, so the text
shipped is the one governing the revision actually in use.

## Contracts and limitations

- **A credit is only as current as the last script run.** Nothing fails a build
  when a new dependency lands without regenerating; `CreditCatalogTests` pins
  the expected names, so that suite is what catches the drift.
- **Development tools are not in the binary.** They are credited because the
  repository makes copies of them, which permissive licenses ask us to
  attribute. Any UI must keep the two kinds visually distinct so a reader isn't
  told something untrue about the app they are running.
- **A missing or unreadable notice is a defect, not a cosmetic gap.** It
  fault-logs and trips an `assertionFailure` in debug; in release
  `licenseText()` returns `nil` so a caller can say the text is unavailable
  rather than render a blank screen that reads like a license with no terms.
- **Names, versions, and license titles are never localized.** They are proper
  nouns and legal terms; a UI supplies the translated framing around them.
