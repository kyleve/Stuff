# Developer tooling

`Tools/` owns importable policy implementations for the repository's public
commands. Read the [repository rules](../AGENTS.md) and [tooling overview](README.md).
These rules also apply when changing a root command or installer that calls this directory.

## Ownership

- Keep public arguments, bootstrap, and process orchestration in the command wrapper.
  Keep parsing and policy in importable modules with direct tests.
  Preserve each command's failure policy when sharing parsers. See PR #284.
- Keep imports free of command execution. Do not turn this private directory
  into a new command framework or distributable package. See PR #283.
- Parse help and usage errors before requiring tools, devices, or network access.
  Preserve composable stdout, diagnostic stderr, child status, and interruption handling.

## Mutations

- Validate inputs before the first mutation. Use the existing `FileTransaction`
  for staged replacements across multiple paths.
- Keep backups until every replacement commits. On apply failure, restore changed paths.
  If rollback fails, retain recovery material and report both errors.
  After commit, report cleanup failures without attempting rollback.
  Guard: [file_transaction_test.rb](Tests/file_transaction_test.rb).
- Require exact registered ownership before simulator deletion.
  A matching name alone never authorizes deletion or transfer of a stale claim.
  Guard: [simulator_registry_test.rb](Tests/simulator_registry_test.rb), PR #288.
- Keep dry runs free of the mutations they preview. Test the public command
  with fake processes and temporary destinations, not developer devices or installed apps.

## Validation

- For policy changes, exercise both the policy and its public command boundary.
  Assert exit status, stdout, stderr, and resulting filesystem or process operations.
  Do not rely only on helper return values.
- Inject failures at the affected write, rename, process, or parsing boundary.
  For ownership or concurrency changes, include stale state and competing processes.
- Preserve the wrapper's supported interpreter and environment contract.
  Include help from an unrelated directory, minimal `PATH`, and paths with spaces or Unicode.
- Use [README testing commands](README.md#testing) and the applicable checks in
  [running-tests](../.agents/skills/running-tests/SKILL.md).
  The [adversarial plan](ADVERSARIAL_TEST_PLAN.md) records the original acceptance scenarios and mutation evidence.
