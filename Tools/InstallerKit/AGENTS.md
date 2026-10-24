# Installer tooling

This directory owns shared app registration, publication, build stamping, and site generation.
See [README.md](README.md) for setup and contracts.
The [tooling rules](../AGENTS.md) and [repository rules](../../AGENTS.md) also apply.

Keep these modules private to the repository.
Use qualified imports under `Tools.InstallerKit` and run commands with `python3 -m` from the repository root.
Use `Tools.repository.repository_root` for checkout resources.
Shared signing policy lives in `signing_profiles.py`; `signing_workflow.rb` orchestrates Match and Gym.
`.github/installer-signing-apps.json` in the trusted checkout selects schemes and targets. Derive bundle IDs from generated build settings.
Setup must match both app registrations on `main` before and after profile refresh. Enable distribution only after both checks and refresh succeed.
PR setup must validate the open same-repository head and mergeability before refresh, enablement, and publication. Preserve concurrent label removal.
Own temporary PR checkouts through failure cleanup. Never remove an existing `installable` label to request another build.
Keep setup dry runs free of prompts, checkout/tool installation, signing, and GitHub mutations. Guard: `test_installer_setup.py`.
Read missing passwords through a hidden terminal prompt; refuse echoed input and never persist the password.
Keep maintenance local and archives read-only. Never load a selected PR's Fastfile or Gemfile.
Enable expired-certificate renewal for local maintenance only; disable it explicitly for archives.
CI signing uses an isolated runner with an empty profile directory and a dedicated read-only deploy key.
Never include raw `security` output or arguments in failure messages. Guard: `SigningStateTest.test_security_failure_never_reports_arguments_or_output`.
Keep temporary keychain/profile ownership in `signing_state.rb`, including partial-failure cleanup.
Guards: `signing_workflow_test.rb`, `signing_state_test.rb`, and `test_signing_profiles.py` under `Tools/Tests`.

## Publication

- Load app identities from the trusted controller's `.github/installer-apps.json`.
  Derive the archive product from the matching trusted signing descriptor; pass the app ID through every CI handoff.
  Keep workflow artifacts and concurrency groups scoped by app. Never infer the app from a PR title or IPA filename.
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
  Manual PR dispatches must retain the label gate and share event-driven PR concurrency groups.
- Advertise updates only after GitHub publishes the verified IPA. Never overwrite a
  published asset. Accept temporary draft asset URLs only under the expected repository.
  Verify the same asset's identity, size, digest, and canonical URL after publication before returning its install URL.
  Deploy the catalog and exact-build manifests together.
  Retired channels must not publish install manifests. Retain their commit history.
- Publish preparing status before archiving and failed status after unsuccessful archive/publication jobs. Keep status scoped to the run and attempt; stale status must not replace newer progress or an equal/newer published release. Status alone never enables installs. Preserve the previous successful build, and clear progress on retirement.
- Show only main installs on the homepage. Put PR builds under their app's page.
  Load site artwork from registered paths in the trusted checkout and publish it with the site.
  Read build details from the signed IPA; keep missing historical details explicit.
  Record optional PR titles from live GitHub metadata at feed publication, never from build receipts. Keep historical titles unchanged.
  Guards: `test_installer_distribution.py`, `test_installer_update_feed.py`,
  `test_installer_update_site.py`, and `test_github_releases.py`.

## Validation

Tests remain under `Tools/Tests` and run through the shared retained-tool suite.
Use fake services and temporary files for publication tests.
