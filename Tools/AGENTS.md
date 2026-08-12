# Tools — Repository Tooling

The independent host-side package under `Tools/Package.swift` owns the Swift
implementation of Stuff's macOS developer commands, while this folder also owns
direct tests for retained cross-platform Python and Ruby tools; see
[`README.md`](README.md). The repository-wide conventions and validation rules
remain in [`../AGENTS.md`](../AGENTS.md).

## Scope and dependencies

- Keep the package independent of the app package so running a developer command
  does not resolve or build application dependencies.
- `StuffToolCore` may import Foundation, Darwin, Dispatch, Synchronization,
  ArgumentParser, and Subprocess. Keep the `StuffTool` executable limited to
  command registration and process-wide signal supervision.
- Preserve the root command shims as the public interface; command implementations
  must not assume the caller's current working directory is the repository root.
- Keep retained Python and Ruby behavior importable without executing its CLI;
  root shell launchers own bootstrap only.

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
Run retained-tool tests with Python unittest discovery and the Ruby Minitest
loader documented in `README.md`; they must likewise avoid Java, TLC, GitHub, and
the real repository filesystem.
