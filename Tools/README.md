# Stuff Tools

`Tools/Package.swift` is the independent macOS command-line package behind the
repository's developer commands. The familiar root paths (`./test`,
`./simulator`, `./xcstrings`, and the app installers) remain the user-facing
interface; their small shims dispatch into the `stuff` executable here.

The package is intentionally separate from the root application package. A tool
build resolves only ArgumentParser and Subprocess, never the iOS application
graph, and tool-only dependencies stay out of shipping targets.

## Development

```bash
swift test --package-path Tools
Tools/run xcstrings --help
```

`Tools/run` uses the committed `Package.resolved` without automatic dependency
updates. Update dependencies explicitly with `swift package resolve
--package-path Tools`, then regenerate the app attribution report because these
packages are credited as development tools.

## Structure

- `Sources/StuffTool` is the executable composition root.
- `Sources/StuffToolCore` contains commands, typed external formats, and injected
  process/filesystem infrastructure.
- `SwiftTests/StuffToolCoreTests` contains fast hermetic Swift Testing suites.
- Existing Python and Ruby tools remain beside this package when they are
  cross-platform or already have an appropriate tested implementation.
