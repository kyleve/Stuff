# Installer tooling

This directory owns shared app registration, publication, build stamping, and site generation.
See [README.md](README.md) for setup and contracts.
The [tooling rules](../AGENTS.md) and [repository rules](../../AGENTS.md) also apply.

Keep these modules private to the repository.
Use qualified imports under `Tools.InstallerKit` and run commands with `python3 -m` from the repository root.
Use `Tools.repository.repository_root` for checkout resources.
Where-specific profile policy and the archive command remain in `Tools/where_signing.py` and `Where/archive`.

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
- Show only main installs on the homepage. Put PR builds under their app's page.
  Load site artwork from registered paths in the trusted checkout and publish it with the site.
  Read build details from the signed IPA; keep missing historical details explicit.
  Guards: `test_installer_distribution.py`, `test_installer_update_feed.py`,
  `test_installer_update_site.py`, and `test_github_releases.py`.

## Validation

Tests remain under `Tools/Tests` and run through the shared retained-tool suite.
Use fake services and temporary files for publication tests.
