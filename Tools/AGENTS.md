# Tools — Repository Tooling

The independent host-side package under `Tools/Package.swift` owns the Swift
implementation of Stuff's macOS developer commands; see [`README.md`](README.md).
The repository-wide conventions and validation rules remain in
[`../AGENTS.md`](../AGENTS.md).

## Scope and dependencies

- Keep the package independent of the app package so running a developer command
  does not resolve or build application dependencies.
- `StuffToolCore` may import Foundation, ArgumentParser, and Subprocess. Keep the
  `StuffTool` executable as a registration-only composition root.
- Preserve the root command shims as the public interface; command implementations
  must not assume the caller's current working directory is the repository root.

## Invariants

- Represent subprocesses as executable plus argument arrays; never construct a
  shell command string.
- Inject process, filesystem, clock, and terminal seams into behavior that needs
  them, and keep parsing/reporting as value transformations.
- Preserve each migrated command's stdout, stderr, and exit-code contract.
- Commands that delete or replace external state expose a non-mutating dry run and
  validate their exact target before changing it.

## Testing

Use Swift Testing through `swift test --package-path Tools`. Tests mirror source
files under `Tools/SwiftTests/StuffToolCoreTests` and use temporary fixture trees
or fake collaborators rather than live Xcode, simulators, devices, or networking.
