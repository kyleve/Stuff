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

Run tests with `mise exec -- tuist test` (or open the generated workspace in Xcode).

The `./ide` script sets `core.hooksPath` to `.githooks`. The pre-commit hook
formats staged Swift with SwiftFormat and runs `./sync-agents --git-add` so
generated Claude files stay in sync with `AGENTS.md`.

## Project structure

```
Project.swift       Tuist project manifest
Tuist.swift         Tuist configuration
.mise.toml          Pins Tuist 4.40.0 and SwiftFormat 0.60.1
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

## License

Apache 2.0 – see [LICENSE](LICENSE).
