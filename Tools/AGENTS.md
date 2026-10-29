# Developer tooling

`Tools/` owns importable policy implementations for the repository's public
commands. Read the [repository rules](../AGENTS.md) and [tooling overview](README.md).
These rules also apply when changing a root command or installer that calls this directory.

## Ownership

- Use `Tools.repository.repository_root` (Python) or `Repository.root` from `Tools/repository.rb` (Ruby) for checkout resources. Resolve from the source file, not the current directory or a fixed parent count.

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

Both websites share the root npm workspace and `astro_site.py` launcher.
Keep each site's data validation and publication policy with its owning tool.
Keep generated Astro and Vite state isolated per invocation.

## Flyover publication

- Keep app registration in `.github/flyover-apps.json`. Keep CircleCI credentials on the GitHub controller, not the capture worker.
- Skip shared cache restore and save for publication builds. Guard: `test_flyover_workflows.py`.
- Report only error categories and HTTP status codes from credential-bearing CircleCI controllers. Never print arbitrary exception text, headers, or response data.
- Publish immutable release bundles only after validation. The existing Pages workflow owns the complete site, including `/flyover/`.
- Run release retention only after successful Pages deployment. Keep seven days, the deployed bundle, and the newest published bundle. Never delete drafts or unrelated releases.
- Reject unsafe ZIP entries, wrong capture identities, dirty captures, and oversized bundles before deployment. Retain the previous release on capture failure.
- Keep filesystem access out of the pure schema, canvas, and image validators.
- Validate, allowlist, and version every declared thumbnail size. Guards: `test_flyover_images.py`, `test_flyover_manifest.py`, `test_flyover_pages.py`.
- Keep publication and recovery in `flyover_publication.py`, not the shell launcher or Astro adapter.
- Use `flyover_artifact_access.py` for descriptor-based access to validated preview files.
- Preserve the previous atlas until installation succeeds. Never overwrite a competing destination during recovery.
  Guards: `test_flyover_publication.py` and the public Flyover command tests.

Shared installer tools have scoped rules in [`InstallerKit/AGENTS.md`](InstallerKit/AGENTS.md).

## Install-site snapshots

- Generate the HTML fixtures through `installer_update_site.render_site` and the production
  [Astro project](InstallerKit/Site/AGENTS.md) during each `ToolsSnapshotTests` build.
  Keep fixture catalogs deterministic and offline. Install dependencies before the build.
  Inline the generated CSS and artwork in those fixtures without changing the rendered layout.
  Do not copy generated HTML into the test sources.
- Capture through `SnapshotKitTesting.assertHTMLSnapshots` in the shared
  `StuffSnapshotTests` scheme. Keep WebKit capture mechanics in SnapshotKitTesting.
  Keep every page state at phone baseline; choose representative page layouts for
  dark/tablet coverage and focused status-page variants for distinct styling or wrapping.
  Guard: [InstallerSiteSnapshotTests.swift](SnapshotTests/InstallerSiteSnapshotTests.swift).

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
