# CreditKit

Tools and types for working out what an app owes attribution to, and for shipping that answer inside the app.

CreditKit holds no credits of its own.
It defines the shape of an **attribution report** and provides the reporting tool that produces one.
Each app runs the report over its own declared sources and ships the result in its own resources.
That split is deliberate.
A report describes one app's dependency graph, so it is that app's data.
A second app can adopt CreditKit without inheriting the first one's credits.

## Install

Add the `CreditKit` product to a target in the root `Package.swift`.
It has no dependencies beyond Foundation.

## Quick start

Run the report (see [Generating a report](#generating-a-report)).
Then decode it wherever the app wants to show it:

```swift
import CreditKit

let report = try AttributionManifest.load(from: .main, resource: "attribution")

for credit in report.credits(ofKind: .library) {
    print(credit.name, credit.version, credit.license.name)
    print(credit.license.text)
}
```

In the Where app that load is wrapped by `WhereCore.AppAttribution`, which knows which of its bundles are expected to carry a report.
`WhereUI`'s `AboutSettingsView` renders one section per kind.

## Public API

- **`AttributionManifest`** — a decoded report. `credits` in report order, `credits(ofKind:)` to filter, `decode(from:)` for raw JSON, and `load(from:resource:)` to read one out of a bundle.
- **`SoftwareCredit`** — one credited work: `name`, `kind`, `version`, `homepageURL`, and its `license`.
- **`SoftwareCredit.Kind`** — `.library` (compiled into the binary) or `.developmentTool` (used to build the project, absent from the shipped app).
- **`LicenseNotice`** — a license's `name` and its verbatim `text`.
- **`AttributionError`** — `.reportMissing(resource:)` when a bundle carries no report. Decoding failures surface as `DecodingError` unwrapped, so the coding path still names the offending field.

## Generating a report

An app declares its sources in an `attribution-sources.json`.
The generator turns that into a manifest:

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
      "manifest": ".agents/external-skills.json" },
    { "type": "developmentTools", "kind": "developmentTool",
      "manifest": ".agents/development-tools.json" }
  ]
}
```

Paths are relative to the repository root.
Three source types are understood:

| Type | Reads | Credits |
|------|-------|---------|
| `swiftPackageManager` | packages a target links via `.product(name:package:)`, pinned by the resolved file | one per linked package |
| `agentSkills` | a `./sync-agents` manifest of `name -> { repo, ref }` | one per vendored skill |
| `developmentTools` | a manifest of `name -> { repo, ref, version? }` for pinned GitHub-hosted tooling the repo uses but does not link as an SPM package | one per entry |

Deriving the list rather than maintaining it is the point.
A package linked by *any* module shows up the next time the report runs.
No module has to remember to vend a credit.
A package declared for tooling alone is never linked, so it is correctly left out.

`swiftPackageManager` derives each credit's **kind** the same way, from `shippedFrom`.
It names the package targets the shipping app and its extensions link.
The generator walks the manifest's target graph out from them.
A package inside that closure is a `library`.
Any other linked package is a `developmentTool`.
Linking is not shipping.
A snapshot-testing engine linked by a test-support target is credited (the repo depends on it) but must not be described as being in the binary.
`shippedFrom` is the only part set by hand.
Adding a dependency cannot quietly land under the wrong kind.

`developmentTools` entries may carry an optional `version` for display.
When omitted, the pinned ref's short prefix is used (as for agent skills).
Keep each entry's `ref` aligned with the revision the repository actually uses.
For example, bump `.agents/development-tools.json` when `./tla-check`'s pinned TLC version changes.

The tool needs network and an authenticated `gh`.
It is idempotent.
Re-running with nothing changed rewrites the same bytes.

The retained-tool Minitest suite exercises package-target parsing, shipping
reachability, source validation, and offline report comparison against temporary
fixtures; run it with the Ruby test-loader command in `Tools/README.md`.

## How it works

Each notice is read from the project's GitHub repository **at the pinned revision**, not the default branch.
The text shipped is the one governing the code actually in use.
Upstream edits notices between releases — a bumped copyright year, a relicense — and reading HEAD would attribute the wrong terms.

Notices are stored **inline** in the manifest rather than as sidecar files.
One decode then yields everything needed to discharge the attribution, with no second lookup that can come back empty, and no missing-file failure path to handle at runtime.

## Contracts and limitations

- **A report goes stale silently unless something checks it.** Nothing about adding or bumping a dependency forces a re-run, so `--check` exists to fail the build.
  It re-derives the expected report from the same manifests and diffs it against the committed one, offline.
  Reach for that rather than asserting credit names in a test.
  A test bundle cannot read the manifests, so it can only compare the report to a literal, which a stale report matches too.
- **Development tools are not in the binary.** They are credited because the repository depends on them — vendored agent skills, pinned verification tooling, and the like — which permissive licenses ask us to attribute.
  Any UI must keep the two kinds visually distinct so a reader is not told something untrue about the app they are running.
- **A missing report is not automatically an error.** Only the app target ships one, so `load` throwing `.reportMissing` is routine in a developer tool or test host.
  CreditKit reports it and leaves the judgement to the caller.
- **Credit names must be unique within a report.** `SoftwareCredit` is `Identifiable` by `name`, so a duplicate breaks list identity in any UI that iterates credits.
  The generator enforces it — a library's name is its repo basename, and two orgs can publish the same one — but a hand-written manifest is on its own.
  The type cannot check what it cannot see.
- **Names, versions, and license titles are never localized.** They are proper nouns and legal terms.
  A UI supplies the translated framing around them.
- **GitHub-hosted sources only.** All manifest-based source types resolve notices through the GitHub API.
  A dependency hosted elsewhere would need a new source type.
