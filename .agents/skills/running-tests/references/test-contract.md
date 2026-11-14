# Repository test contract

## Running tests

**Use [`./test`](../../../../test)** — the only way to run the iOS bundles. Never hand-roll
`tuist test` or `xcodebuild` for them. The command
runs the host-side backup-upgrader regression for affected or unit-capable iOS
scopes. Snapshot-only runs skip this regression. Every normal invocation runs
the Bumper Bowling checks first. **Run checks in proportion to risk.** Run
`./swiftformat --lint` when the changed files are in its scope. Run the
narrowest applicable `./test` tier for code, build, tooling, or behavior
changes. Pure documentation or comment-only changes can skip checks that
cannot exercise them. Record skipped checks in the commit or PR validation.
Semantic changes to configuration, scripts, generator inputs, executable
examples, or app-rendered copy are not documentation-only.

`./test PeriscopeMacrosTests` runs the host-side macro suite without selecting a simulator. `./test --all` and `./test --everything` include it. `./test --snapshots` alone does not.

When another invocation owns the attribution, backup-upgrader, and macro tests, you can use `--skip-host-tests`.
CircleCI delegates these checks to the required GitHub macOS job.
Artifact consumers also skip host checks. Normal local runs retain their default checks.

Load the [`running-tests`](../SKILL.md) skill for
test tiers, snapshot opt-in, why not `tuist test`, and per-checkout simulator
management (`./simulator` resolves a UDID — never pass a device name to
`simctl`). Development commands default to the iOS 27.2 Simulator runtime.
Snapshot runs require the Xcode major.minor version in
[`.xcode-version`](../../../../.xcode-version). `./test` checks it before it
generates the project or starts a simulator.
