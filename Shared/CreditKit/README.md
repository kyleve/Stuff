# CreditKit

Tools and types for working out what an app owes attribution to, and for
shipping that answer inside the app.

CreditKit holds no credits of its own. It defines the shape of an **attribution
report** and provides the reporting tool that produces one; each app runs the
report over its own declared sources and ships the result in its own resources.
That split is deliberate — a report describes one app's dependency graph, so it
is that app's data, and a second app can adopt CreditKit without inheriting the
first one's credits.

## Install

Add the `CreditKit` product to a target in the root `Package.swift`. It has no
dependencies beyond Foundation.

## Quick start

Run the report (see [Generating a report](#generating-a-report)), then decode it
wherever the app wants to show it:

```swift
import CreditKit

let report = try AttributionManifest.load(from: .main, resource: "attribution")

for credit in report.credits(ofKind: .library) {
    print(credit.name, credit.version, credit.license.name)
    print(credit.license.text)
}
```

In the Where app that load is wrapped by `WhereCore.AppAttribution`, which knows
which of its bundles are expected to carry a report, and `WhereUI`'s
`AboutSettingsView` renders one section per kind.

## Public API

- **`AttributionManifest`** — a decoded report. `credits` in report order,
  `credits(ofKind:)` to filter, `decode(from:)` for raw JSON, and
  `load(from:resource:)` to read one out of a bundle.
- **`SoftwareCredit`** — one credited work: `name`, `kind`, `version`,
  `homepageURL`, and its `license`.
- **`SoftwareCredit.Kind`** — `.library` (compiled into the binary) or
  `.developmentTool` (used to build the project, absent from the shipped app).
- **`LicenseNotice`** — a license's `name` and its verbatim `text`.
- **`AttributionError`** — `.reportMissing(resource:)` when a bundle carries no
  report. Decoding failures surface as `DecodingError` unwrapped, so the coding
  path still names the offending field.

## Generating a report

An app declares its sources in an `attribution-sources.json`, and the generator
turns that into a manifest:

```bash
./attribution                                           # every configured app
ruby Shared/CreditKit/Tools/generate-attribution.rb <config.json>   # just one
```

```json
{
  "output": "Where/Where/Resources/attribution.json",
  "sources": [
    { "type": "swiftPackageManager", "manifest": "Package.swift",
      "resolved": "Package.resolved", "shippedFrom": ["WhereUI"] },
    { "type": "agentSkills", "kind": "developmentTool",
      "manifest": ".agents/external-skills.json" }
  ]
}
```

Paths are relative to the repository root. Two source types are understood:

| Type | Reads | Credits |
|------|-------|---------|
| `swiftPackageManager` | packages a target links via `.product(name:package:)`, pinned by the resolved file | one per linked package |
| `agentSkills` | a `./sync-agents` manifest of `name -> { repo, ref }` | one per vendored skill |

Deriving the list rather than maintaining it is the point: a package linked by
*any* module shows up the next time the report runs, so no module has to
remember to vend a credit — and a package declared for tooling alone is never
linked, so it is correctly left out.

`swiftPackageManager` derives each credit's **kind** the same way, from
`shippedFrom`: it names the package targets the shipping app and its extensions
link, the generator walks the manifest's target graph out from them, and a
package inside that closure is a `library` while any other linked package is a
`developmentTool`. Linking is not shipping — a snapshot-testing engine linked by
a test-support target is credited (the repo depends on it) but must not be
described as being in the binary. `shippedFrom` is the only part set by hand, so
adding a dependency can't quietly land under the wrong kind.

The tool needs network and an authenticated `gh`. It is idempotent: re-running
with nothing changed rewrites the same bytes.

## How it works

Each notice is read from the project's GitHub repository **at the pinned
revision**, not the default branch, so the text shipped is the one governing the
code actually in use. Upstream edits notices between releases — a bumped
copyright year, a relicense — and reading HEAD would attribute the wrong terms.

Notices are stored **inline** in the manifest rather than as sidecar files. One
decode then yields everything needed to discharge the attribution, with no
second lookup that can come back empty, and no missing-file failure path to
handle at runtime.

## Contracts and limitations

- **A report is only as current as its last run.** Nothing fails a build when a
  dependency lands without regenerating. Each app is expected to assert its own
  report's contents in its own tests — see `AppAttributionTests` in the Where
  app — because only the app knows what it should contain.
- **Development tools are not in the binary.** They are credited because the
  repository makes copies of them, which permissive licenses ask us to
  attribute. Any UI must keep the two kinds visually distinct so a reader isn't
  told something untrue about the app they are running.
- **A missing report is not automatically an error.** Only the app target ships
  one, so `load` throwing `.reportMissing` is routine in a developer tool or
  test host. CreditKit reports it and leaves the judgement to the caller.
- **Credit names must be unique within a report.** `SoftwareCredit` is
  `Identifiable` by `name`, so a duplicate breaks list identity in any UI that
  iterates credits. The generator enforces it — a library's name is its repo
  basename, and two orgs can publish the same one — but a hand-written manifest
  is on its own; the type can't check what it can't see.
- **Names, versions, and license titles are never localized.** They are proper
  nouns and legal terms; a UI supplies the translated framing around them.
- **GitHub-hosted sources only.** Both source types resolve notices through the
  GitHub API; a dependency hosted elsewhere would need a new source type.
