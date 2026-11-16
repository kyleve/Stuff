# CreditKit — Module Shape

CreditKit owns attribution types and report generation. See [README.md](README.md) and the [root contract](../../AGENTS.md).

## Scope & dependencies

Foundation only, including no logging. Presentation belongs to consumers.
[The generator](Tools/generate-attribution.rb) is the sole report writer.

## Invariants

- CreditKit ships no credits or notices. Each app declares its report sources and carries the generated resource.
- Module tests use fixtures; assertions about real dependencies belong in the app's tests.
- Report load failures throw. Do not log or substitute an empty manifest.
- Preserve wire values. UI must visually distinguish library and development-tool credits.
- Read notices at the pinned revision.
- SPM attribution follows linked `.product(name:package:)` uses. Library classification follows `shippedFrom` reachability, stopping at macro targets; other linked packages are development tools.
- External skill/tool kind comes from attribution configuration.

## Testing

`CreditKitTests` checks format/API behavior with a literal wire fixture in `CreditKitTestSupport.swift`.
App tests check the bundled report; `./attribution --check` checks dependency drift.
