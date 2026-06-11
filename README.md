# Stuff

Random apps and stuff.

## Requirements

- Xcode 26+
- [mise](https://mise.jdx.dev) (pins Tuist and SwiftFormat)
- iOS 26.0+

## Getting started

```bash
# Install mise (if needed)
brew install mise

# Install pinned tools (Tuist, SwiftFormat)
mise install

# Generate the Xcode project (also sets Git hooks and runs sync-agents --install)
./ide

# Or install Tuist package dependencies first, then generate
./ide -i
```

Run tests with `mise exec -- tuist test` (or open the generated workspace in Xcode). CI pins an iOS Simulator destination so the full suite stays consistent.

The `./ide` script sets `core.hooksPath` to `.githooks`. The pre-commit hook
formats staged Swift with SwiftFormat and runs `./sync-agents --git-add` so
generated Claude files stay in sync with `AGENTS.md`.

## Signing for on-device builds

The checked-in project intentionally has **no** development team, so building
to a simulator works for everyone and nothing machine-specific lands in Git.
To build to a physical device you need to supply your Apple Developer Team ID.

`Project.swift` reads it from the `TUIST_DEVELOPMENT_TEAM` environment variable
and, when present, stamps it into the generated project as `DEVELOPMENT_TEAM`.
The value lives in `.mise.local.toml` — a local, **gitignored** mise config —
so `mise exec -- tuist generate` (i.e. `./ide`) picks it up automatically and
your team survives every regeneration. No team set (CI, fresh clones) means no
`DEVELOPMENT_TEAM` is written and Xcode behaves as before.

Set it once:

```bash
# Writes TUIST_DEVELOPMENT_TEAM to .mise.local.toml, then regenerates
./ide --team-id ABCDE12345
```

Find your Team ID in Xcode › Settings › Accounts (the "Team ID" column) or at
[developer.apple.com/account](https://developer.apple.com/account) under
Membership details. You can also edit `.mise.local.toml` by hand:

```toml
[env]
TUIST_DEVELOPMENT_TEAM = "ABCDE12345"
```

## Project structure

```
Package.swift       Local Swift package (StuffCore, WhereCore, WhereUI, WhereTesting)
Project.swift       Tuist manifest (Where app, StuffTestHost, test bundles → SPM)
Tuist.swift         Tuist configuration
.mise.toml          Pins Tuist 4.40.0 and SwiftFormat 0.60.1
.mise.local.toml    Local mise overrides, gitignored (e.g. TUIST_DEVELOPMENT_TEAM)
.swiftformat        SwiftFormat rules
ide                 Dev script – hooks, sync-agents, tuist generate
swiftformat         Run SwiftFormat via mise (default: format `.`)
sync-agents         Sync AGENTS.md → CLAUDE.md and .claude/skills/
.githooks/          Git hooks (pre-commit)
.agents/            External skills manifest (`external-skills.json`)
AGENTS.md           Repository shape for AI agents
Shared/StuffCore/   Shared iOS framework (Sources/, Tests/)
Shared/StuffTestHost/  Shared iOS unit-test host app (Sources/)
Where/              Where iOS app, modules, and tests
```

## Acknowledgements

The Where module bundles offline region polygons under
[`Where/WhereCore/Sources/Resources/`](Where/WhereCore/Sources/Resources/).
US state boundaries come from
[eric.clst.org/tech/usgeojson](https://eric.clst.org/tech/usgeojson/)
(`gz_2010_us_040_00_5m.json`), converted from the
[US Census Bureau Cartographic Boundary Files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html);
US Government works are in the public domain. See
[`Where/WhereCore/Sources/Resources/README.md`](Where/WhereCore/Sources/Resources/README.md)
for per-file provenance.

## License

Apache 2.0 – see [LICENSE](LICENSE).
