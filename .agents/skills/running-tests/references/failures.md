# Test failure diagnosis

## Simulator launch

Use `./simulator --help` for device/runtime selection and ownership operations.
A checkout's first boot can take several minutes.

If executed suites pass but launch reports `Application failed preflight checks (Busy)`, `Mach error -308 — server died`, or `crashed with signal kill before establishing connection`, recreate that checkout's device with `./simulator --recreate`, then rerun `./test`.

For a necessary one-off Xcode operation outside iOS test-bundle execution, use:

```sh
-destination "platform=iOS Simulator,id=$(./simulator)"
```

## CI-only failures

Compare the provider's tested revision, toolchain, and selected suites through [github-workflow](../../github-workflow/references/merging.md#merging-main-and-other-branches).
A failing check alone does not establish a branch conflict.
