# Installer tooling

This directory owns shared app registration, publication, build stamping, and site generation.
See [README.md](README.md) for setup and contracts.
The [tooling rules](../AGENTS.md) and [repository rules](../../AGENTS.md) also apply.

Keep these modules private to the repository.
Use qualified imports under `Tools.InstallerKit` and run commands with `python3 -m` from the repository root.
Use `Tools.repository.repository_root` for checkout resources.
Shared signing policy lives in `signing_profiles.py`; `signing_workflow.rb` orchestrates Match and Gym.
`.github/installer-signing-apps.json` in the trusted checkout selects schemes and targets. Derive bundle IDs from generated build settings.
Keep maintenance local and archives read-only. Never load a selected PR's Fastfile or Gemfile.
Enable expired-certificate renewal for local maintenance only; disable it explicitly for archives.
CI signing uses an isolated runner with an empty profile directory and a dedicated read-only deploy key.
Never include raw `security` output or arguments in failure messages. Guard: `SigningStateTest.test_security_failure_never_reports_arguments_or_output`.
Keep temporary keychain/profile ownership in `signing_state.rb`, including partial-failure cleanup.
Guards: `signing_workflow_test.rb`, `signing_state_test.rb`, and `test_signing_profiles.py` under `Tools/Tests`.

## Publication

- Load app identities from the trusted controller's `.github/installer-apps.json`.
  Namespace release tags, manifest paths, catalog mutations, and channel pages by app ID.
  An app ID cannot change its bundle identifier. Preserve other apps and channels on writes.
- Run signed archives on the shared CircleCI macOS executor. Keep its config and control checkout on `main`.
  Require the signing context's project and config-source restrictions. Keep the CircleCI API token on the GitHub controller.
  Validate a successful pipeline, job, artifact path, and signed run identity before publication.
- Keep repository write credentials out of archive jobs. Only same-repository PRs
  labeled `installable` may receive signed branch builds. Use a controller from `main`.
- Use `pull_request_target` so conflicts cannot suppress retirement. Require confirmed
  absence of merge conflicts before signing or publishing. Recheck the live SHA and label
  before publishing or retiring. Serialize mutations per app and channel.
- Advertise updates only after GitHub publishes the verified IPA. Never overwrite a
  published asset. Deploy the catalog and exact-build manifests together.
  Retired channels must not publish install manifests. Retain their commit history.
- Deploy the site independently of archive enablement and signing configuration.
  If the publication branch is absent, serve an empty schema-3 catalog.
  Fail deployment on unreadable or invalid catalogs, including a missing catalog on an existing branch.
  Guards: `test_installer_update_feed.py` and `test_installer_update_site.py`.
- Show only main installs on the homepage. Put PR builds under their app's page.
  Load site artwork from registered paths in the trusted checkout and publish it with the site.
  Read build details from the signed IPA; keep missing historical details explicit.
  Guards: `test_installer_distribution.py`, `test_installer_update_feed.py`,
  `test_installer_update_site.py`, and `test_github_releases.py`.

## Validation

Tests remain under `Tools/Tests` and run through the shared retained-tool suite.
Use fake services and temporary files for publication tests.
