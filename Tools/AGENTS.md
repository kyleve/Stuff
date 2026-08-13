# Tools — Repository Tooling

The independent host-side package under `Tools/Package.swift` owns the Swift
implementation of Stuff's Xcode- and device-heavy macOS developer commands.
This folder also owns direct tests for retained Python and Ruby tools. See
[`README.md`](README.md). Repository-wide conventions and validation rules are
in [`../AGENTS.md`](../AGENTS.md).

## Scope and dependencies

- Keep the package independent of the app package. A developer command must not
  resolve or build application dependencies.
- `StuffToolCore` may import Foundation, Darwin, Dispatch, Synchronization,
  ArgumentParser, and Subprocess. Keep the `StuffTool` executable limited to
  command registration, parser termination, and exit-status mapping.
- Preserve the root command shims as the public interface. Command
  implementations must not assume that the caller's current working directory
  is the repository root.
- Keep retained Python and Ruby behavior importable without executing its CLI.
  Root shell launchers own bootstrap only.

## Invariants

- Represent subprocesses as an executable plus an argument array. Never
  construct a shell command string.
- Leave spawned commands in the caller's foreground process group so
  terminal-generated job-control signals reach the command tree without a
  custom supervisor.
- Inject process, filesystem, clock, and terminal seams into behavior that needs
  them. Keep parsing and reporting as value transformations.
- Share workspace generation, build-settings lookup, logged `xcodebuild`, and
  typed xcresult export through `XcodeWorkspace`; commands own their distinct
  failure and reporting semantics.
- Preserve each migrated command's stdout, stderr, and exit-code contract.
- Commands that delete or replace external state expose a non-mutating dry run and
  validate their exact target before changing it.

## Testing

Use Swift Testing through `swift test --package-path Tools`. Tests mirror source
files under `Tools/SwiftTests/StuffToolCoreTests`. Use temporary fixture trees or
fake collaborators instead of live Xcode, simulators, devices, or networking.
Run retained-tool tests with Python unittest discovery and the Ruby Minitest
loader documented in `README.md`. Those tests must also avoid Java, TLC, GitHub,
and the real repository filesystem.
