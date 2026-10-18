# Developer tooling

`Tools/` owns importable policy implementations for the repository's public
commands. Read the [repository rules](../AGENTS.md) and [tooling overview](README.md).
These rules also apply when changing a root command or installer that calls this directory.

## Ownership

- Keep public arguments, bootstrap, and process orchestration in the command wrapper.
  Keep parsing and policy in importable modules with direct tests.
  Preserve each command's failure policy when sharing parsers.
- Keep imports free of command execution. Do not turn this private directory
  into a new command framework or distributable package.
- Parse help and usage errors before requiring tools, devices, or network access.
  Preserve composable stdout, diagnostic stderr, child status, and interruption handling.

## Mutations

- Validate inputs before the first mutation. Use the existing `FileTransaction`
  for staged replacements across multiple paths.
- Keep backups until every replacement commits. On apply failure, restore changed paths.
  If rollback fails, retain recovery material and report both errors.
  After commit, report cleanup failures without attempting rollback.
  Guard: [file_transaction_test.rb](Tests/file_transaction_test.rb).
- Before deleting a checkout's simulator, require a registry claim for that checkout, device model, and OS.
  Match the claim's UDID, expected name, and runtime to `simctl` inventory.
  A matching name alone never authorizes deletion or transfer of a stale claim.
  Guard: [simulator_registry_test.rb](Tests/simulator_registry_test.rb).
- Keep dry runs free of the mutations they preview. Test the public command
  with fake processes and temporary destinations, not developer devices or installed apps.

## Snapshot shard plans

- Keep measured timings in balance reports, not the persisted execution plan.
- Preserve assignments unless intake, the improvement threshold, or an explicit shard-count change requires an update.
  Guard: [test_snapshot_shards.py](Tests/test_snapshot_shards.py).

## Installer publication

- Load app identities from the trusted controller's `.github/installer-apps.json`.
  Namespace release tags, manifest paths, catalog mutations, and channel pages by app ID.
  An app ID cannot change its bundle identifier. Preserve other apps and channels on writes.
- Keep repository write credentials out of archive jobs. Only same-repository PRs
  labeled `installable` may receive signed branch builds. Use a controller from `main`.
- Use `pull_request_target` so conflicts cannot suppress retirement. Require confirmed
  absence of merge conflicts before signing or publishing. Recheck the live SHA and label
  before publishing or retiring. Serialize mutations per app and channel.
- Advertise updates only after GitHub publishes the verified IPA. Never overwrite a
  published asset. Deploy the catalog and exact-build manifests together.
  Retired channels must not publish install manifests. Retain their commit history.
- Show only main installs on the homepage. Put PR builds under their app's page.
  Load site artwork from registered paths in the trusted checkout and publish it with the site.
  Read build details from the signed IPA; keep missing historical details explicit.
  Guards: `test_installer_distribution.py`, `test_installer_update_feed.py`,
  `test_installer_update_site.py`, and `test_github_releases.py`.

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
