# Stuff

Random apps and stuff.

## Requirements

- Xcode 26+
- [mise](https://mise.jdx.dev) (manages Tuist version)
- iOS 26.0+

## Getting started

```bash
# Install mise (if needed)
brew install mise

# Generate the Xcode project
./ide

# Or install dependencies first, then generate
./ide -i
```

## Project structure

```
Project.swift       Tuist project manifest
Tuist.swift         Tuist configuration
.mise.toml          Pins Tuist 4.40.0
ide                 Dev script – regenerates Xcode project
AGENTS.md           Repository shape for AI agents
```

## License

Apache 2.0 – see [LICENSE](LICENSE).
