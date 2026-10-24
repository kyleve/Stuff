# Install Where Dev through GitHub

[InstallerKit](../Shared/InstallerKit/README.md) supplies the shared update engine.
The [installer guide](../Tools/InstallerKit/README.md) covers adding apps to the common site.
GitHub Releases hosts signed IPAs. GitHub Pages hosts the install site, OTA manifests, and update catalog.
The [distribution workflow](../.github/workflows/installer-distribution.yml) publishes these channels:

| Channel | Trigger | Availability |
| --- | --- | --- |
| `main` | Push to `main`, or a manual run on `main` | Latest successful build |
| `pr-<number>` | Add `installable` to a PR in this repository | Latest successful build while the PR is open and labeled |

Open [the install site](https://kyleve.github.io/Stuff/) in Safari on a registered iPhone or iPad.
The homepage lists main builds for all registered apps.
Open `/apps/where/` for Where PR builds.
Select **Install Where Dev**, then confirm the iOS installation prompt.
The workflow summary links directly to the channel page after publication.
The page becomes available after **App Install Site** completes.
Bookmark `/apps/where/main/` for routine installs.

Removing `installable` or closing the PR retires its page and removes its manifests from the next Pages deployment.
The retired page remains at the same URL and links to available builds.
Historical release assets remain publicly downloadable. Retirement does not revoke a downloaded app or an old cached manifest.

All channels install **Where Dev**, with compiler optimizations and developer tools enabled.
They use the Development identity from [Project.swift](../Project.swift), with its local store.
Installing another channel replaces Where Dev and keeps that app's data.
Branches do not install side by side.
Where Beta and the App Store app keep their separate identity and store.

## One-time setup

The workflow stays disabled until the repository variable `WHERE_DISTRIBUTION_ENABLED` is `true`.
Complete these steps before enabling it.
The repository must be public. Publication uses GitHub's built-in `GITHUB_TOKEN`.
CircleCI builds the signed IPA. GitHub Actions uses a separate CircleCI API token to request and retrieve that build.
The IPA, manifest, commit notes, and build metadata are public.
Apple's ad hoc profile still restricts installation to registered devices.
The provisioning profile inside the IPA includes those device identifiers.

1. Install the locked tools with `./ide --install --no-open`.
   Set the Apple Developer team with `./ide --team-id TEAM --no-open`.
2. In the Apple Developer portal, create the explicit app IDs and enable these capabilities.
   [Project.swift](../Project.swift) owns the identifiers and entitlements.
   Fastlane creates certificates and profiles. It does not configure these capabilities.

   | Target | Current app identifier | Capabilities |
   | --- | --- | --- |
   | Where | `com.stuff.where.development` | Development App Group, iCloud, Push Notifications |
   | WhereWidgets | `com.stuff.where.development.widgets` | Development App Group |
   | WhereShareExtension | `com.stuff.where.development.share` | Development App Group |

   Associate all three IDs with `group.com.stuff.where.development`.
   Associate the host app with the CloudKit container `iCloud.com.stuff.where`.
   Include these capabilities even though Development uses the local store.
   Register at least one iPhone or iPad in the Apple Developer portal.
3. Create an App Store Connect **Team API key** with access to Certificates, Identifiers & Profiles.
   Individual API keys cannot manage provisioning.
   Store its [Fastlane JSON file](https://docs.fastlane.tools/app-store-connect-api/#using-an-app-store-connect-api-key)
   outside the checkout, with permissions `600`.
   Set `INSTALLER_API_KEY_PATH` to that file's absolute path for local maintenance.
   Do not put this key in CI.
4. Use the private [Stuff-Signing repository](https://github.com/kyleve/Stuff-Signing), on branch `main`.
   Local maintenance needs SSH write access through your own GitHub account.
   Store a strong encryption password in your password manager and supply it as `MATCH_PASSWORD`.
   Use the same password locally and in CI. Do not commit or print it.
   Run `./signing refresh --app where` to create the initial certificate and all three profiles.
   Refresh regenerates every profile, including after a capability or device change.
   It does not revoke unrelated certificates. It never calls `match nuke`.
   Apple and Git updates are not atomic. If maintenance fails partway, fix the reported error and rerun it.
5. Create the CircleCI context `where-distribution-signing`, restricted to this project.
   Add these values to the context, not project-wide environment variables:

   | Variable | Value |
   | --- | --- |
   | `TUIST_DEVELOPMENT_TEAM` | The Apple Developer team ID |
   | `MATCH_PASSWORD` | The signing repository encryption password |
   | `MATCH_DEPLOY_KEY` | A dedicated SSH private key with read-only deploy access to Stuff-Signing |

   Remove the former `WHERE_DISTRIBUTION_CERTIFICATE_*` and `WHERE_*_PROFILE_BASE64` secrets, if present.
   CI needs no Apple API key, Apple account password, or signing-repository write access.

   Use CircleCI's context secret form to enter the values. Do not commit or print them.
   Add this context expression restriction before enabling distribution:

   ```text
   pipeline.config.repository.name == "kyleve/Stuff"
   and pipeline.config.ref == "refs/heads/main"
   and pipeline.config.file_path == ".circleci/config.yml"
   and pipeline.git.branch == "main"
   and not job.ssh.enabled
   and not (pipeline.config_source starts-with "api")
   ```

   This restriction is enforced outside the PR's editable workflow configuration.
   It permits an API-triggered pipeline whose configuration comes from GitHub `main`.
   It rejects unversioned configuration submitted through the API.
   See [CircleCI context restrictions](https://circleci.com/docs/guides/security/contexts/#expression-restrictions).
6. In CircleCI, select the GitHub App pipeline definition for this repository's `.circleci/config.yml`.
   The controller requests `main` for both configuration and checkout.
   Add these values in GitHub Settings → Secrets and variables → Actions:

   | Name | Type | Value |
   | --- | --- | --- |
   | `INSTALLER_CIRCLECI_PROJECT` | Variable | The project slug from CircleCI Project Settings → Overview |
   | `INSTALLER_CIRCLECI_PIPELINE` | Variable | The definition ID from CircleCI Project Settings → Pipelines |
   | `INSTALLER_CIRCLECI_TOKEN` | Secret | A CircleCI API token authorized to trigger that pipeline and read its artifacts |

   Keep this API token out of CircleCI's signing context and project environment.
   GitHub's Linux controller uses it without checking out or running PR code.
   See [CircleCI's trigger API](https://circleci.com/docs/api/v2/index.html#operation/triggerPipelineRun).
7. In GitHub Settings → Actions → Policies, allow this workflow's `push`, `workflow_dispatch`, and `pull_request_target` events.
   Scope the event policy to `.github/workflows/installer-distribution.yml`.
   GitHub's default policy can block `pull_request_target` in public repositories.
   See [workflow execution policies](https://docs.github.com/en/actions/how-tos/administer/control-workflow-execution).
8. In GitHub Settings → Pages, select **GitHub Actions** as the publishing source.
   Allow `workflow_dispatch` for `.github/workflows/installer-pages.yml` in the Actions event policy.
   The default feed URL is `https://kyleve.github.io/Stuff/updates.json`.
   If Pages uses a custom domain, set `INSTALLER_FEED_URL` to its HTTPS catalog URL before building.
9. Create the repository label `installable` if it does not exist.
   Merge the integration into `main`, then set `WHERE_DISTRIBUTION_ENABLED` to `true`.
   Run **App Dev Distribution** manually on `main` to publish the first build.
   Open its install link on a registered phone and verify launch, widgets, and sharing.
   Add `installable` to an open PR, then push again to verify that its page updates.

To add a device, run this command locally, then publish a new build:

```bash
./signing register-device --app where --name "My iPhone" --udid DEVICE_UDID
```

Registration refreshes every app and extension profile.
Both maintenance commands replace expired certificates and regenerate all profiles. They retain certificates that are still valid.
If a certificate expires, run `./signing refresh --app where` locally, then publish a new build.
Ordinary archives use Match in read-only mode and cannot repair missing or expired assets.
The Apple Distribution certificate signs the app. GitHub provides the HTTPS certificate for downloads.
See Apple's [ad hoc profile guide](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/).

## Build and publication behavior

PR events use a `pull_request_target` controller from `main`.
The **Check installable build** job fails for labeled PRs with conflicts, before the archive job receives signing secrets.
Resolve the conflicts and push again to retry.
If GitHub is still checking for conflicts, the controller retries for up to 30 seconds.
If the result stays unknown, the job fails and requests a rerun.

The workflow builds the PR's head commit, including PRs stacked on other branches.
Fork PRs do not receive signing secrets or distribution pages.
The `installable` label authorizes a signed build of that PR's code and later commits.
The archive uses CircleCI's `m4-pro-medium` executor, shared with the other macOS jobs.
It checks the pinned Xcode build before running branch code.

The label is a signing trust decision, not a sandbox boundary.
Build scripts and dependencies from that branch can access the signing identity while the archive runs.
Only label code whose authors and subsequent commits are trusted with that access.
The temporary keychain and cleanup limit persistence. They do not prevent a malicious build from copying signing material.

The archive job uses a temporary keychain and removes its signing files after the job.
It validates each profile's expiry, device list, team, and generated target settings before archiving.
Fastlane signs the app and both extensions during the archive, then exports an ad hoc IPA.
The pinned Gym uses `ad-hoc`, which Xcode accepts as an alias for `release-testing`.
CI requires an isolated runner with an empty Xcode provisioning-profile directory.
The helper refuses existing profiles before it changes keychains.
Cleanup restores the original keychain search list and removes job-owned profiles and the temporary keychain.
It never changes the default keychain.
The archive job has no GitHub write token or CircleCI API token.
Its configuration, Fastfile, Gemfile lock, signing helper, eligibility checks, cleanup, and IPA validation come from `main`.
The selected branch supplies the app source and project generation scripts.
Older branches do not need a Fastfile or Gemfile.
It rechecks the live PR before checking out the requested commit into a separate source directory.
Only the final IPA is stored as a CircleCI artifact. Signing state is never uploaded.
GitHub accepts the artifact only after that pipeline and archive job succeed.
It validates the signed commit, app, channel, run, attempt, and feed URL before passing the IPA to publication.

The publication job uses control scripts from `main` and a repository write token.
It validates the IPA's Development identity, build configuration, commit stamp, bundle version, and signing resources.
It checks the live branch SHA, PR label, and merge conflicts before publication.
Retirement checks the live label and PR state, even when conflicts exist.
Runs for one channel are serialized. Stale events cannot replace newer catalog entries or retire a newly relabeled channel.
A conflict or failed archive leaves the previous hosted build available.
Publication does not wait for the separate test workflows.

Each archive gets a distinct prerelease: `installer-where-<channel>-<run>-<attempt>`.
The publisher uploads `app.ipa` to a draft, validates its SHA-256 digest and size, then publishes it.
GitHub gives draft assets temporary URLs. After publication, the publisher verifies the same asset and its final tag URL before catalog publication.
A retry reuses a matching release and asset. It never overwrites a published IPA.
If an upload or verification fails, inspect the draft before retrying.
The release does not become GitHub's latest stable release.

Release tags point to trusted `main` at publication time.
GitHub's workflow token cannot create tags at PR commits that change workflow files.
The release notes and signed IPA stamp identify the actual source commit.
Do not use the release tag's source archive as the source of a PR build.
See [GitHub's release API](https://docs.github.com/en/rest/releases/releases#create-a-release).

An error during signing cleanup retains recovery files and fails the job.
The cleanup log identifies their directory.

## Checking for updates in the app

A CI Development build checks its channel when the app enters the foreground.
A successful result is reused for one hour. **Settings > App Updates > Check for Updates** checks immediately.
A Settings tab badge indicates an available update. **App Updates** stays first in Settings, including when the installed build is current.
The badge remains until the available build is installed.

**App Updates** lists incoming commits since the installed build, including skipped builds.
Each commit opens on GitHub. **Install Update** opens the iOS installer directly for that exact build.
The user confirms installation in the system prompt.
If a PR channel closes, the screen offers **Switch to Main** when main has a published build.
This action requires an explicit selection.

**Other Builds** lists Main and active PR channels. Open a channel to install its latest build.
**Build History** also offers retained older builds. The exact installed build has a marker.
Browsing does not change the update channel or badge. After installation, update checks follow the new build's channel.
These build notes compare the selected release with its own predecessor, not with the installed build.

A failed check preserves the last result and shows its check date with the error.
Rewritten or unavailable commit history is labeled instead of shown as a complete list.
Local Development builds from Xcode, `Where/install`, or a local archive also show App Updates and Other Builds.
They display the Local channel and their recorded Git status. They have no automatic update badge or incoming-commit comparison.
Use Other Builds to install Main or a PR. Install again from Xcode or `./Where/install` to return to Local.
The bundle identity stays the same; Local has no hosted binary or in-app download action.
Beta, App Store, and demo mode do not check this feed.
This version checks only in the foreground.

After setup, verify these paths on a registered phone:

1. Install one CI build from the site. Verify launch, widgets, and sharing.
2. Publish another build. Verify the Settings badge, commit links, and direct install action.
3. Open and return from App Updates. Verify that the badge remains until installation.
4. Retire the PR channel. Verify the explicit switch to main and the retired site page.
5. Disconnect the phone from the network. Verify that the last update result remains visible with the check error.
6. Use Other Builds to install Main, two different PR builds, and Main again. Verify that update checks follow each installed channel.
7. Install an older retained build. Verify its installed marker and the badge for the newer build.
8. Retire a channel while its build details are open. Refresh and verify that the install action disappears.
9. Install a dirty local checkout with `./Where/install`. Verify the Local metadata, first Settings row, and absence of an update badge.
10. Install a remote build through Other Builds, then reinstall through Xcode or `./Where/install`. Verify the return to Local with retained app data.

Automated tests do not prove installation on a physical device.

## Update catalog and install site

After release publication, the publisher updates `updates.json` on the `installer-update-feed` branch.
A retirement marks the channel inactive in that catalog.
Compare-and-swap writes preserve simultaneous changes to different apps and channels.
The publisher then requests **App Install Site**.
That workflow reads the latest catalog and generates the site with control scripts from `main`.
The complete catalog and all manifests ship in one Pages artifact.

The schema version is `3`. The catalog groups channels under registered apps. Each release records its exact manifest URL, GitHub asset URL, and bundle version.
A manifest uses the Development bundle identifier and the exported IPA's `CFBundleVersion`.
The app accepts only manifests under the signed feed URL's directory, with matching app, channel, run, and attempt.
The app constructs the `itms-services` link locally. It contains no GitHub credentials.

Each channel retains its latest 100 catalog entries and incoming commits between them.
Active channels retain a manifest for each of those entries.
Older installs can still see the latest build, but can lose complete commit notes when their baseline leaves the catalog.
Release assets have no automatic cleanup in this integration.
The catalog marks rewritten or unavailable ancestry explicitly.
Retirement preserves catalog history.

A failed catalog write fails the publication job. Its uploaded release remains on GitHub.
Rerun the failed publication job to retry the catalog write with the existing GitHub archive artifact.
To rebuild, rerun the GitHub archive job or the full controller. Do not rerun only the CircleCI workflow.
The controller retains GitHub run and attempt numbers as the build identity.
A controller timeout does not stop the CircleCI job. Inspect that pipeline before retrying.
If the catalog write succeeds but deployment fails, rerun **App Install Site** on `main`.
The app sees the previous complete Pages deployment until the replacement succeeds.

CI stamps the app ID, repository, channel, full commit, run ID, attempt, and feed URL into the signed app.
Run ID and attempt establish build order within a channel.
An older run cannot replace a newer catalog entry, even when rerun.
Local builds use the Development defaults in `Project.swift`: app ID, repository, feed URL, and the explicit `local` channel.
CI metadata overrides those defaults. A local rebuild clears the previous run and attempt.
Local revisions can be clean, dirty, or unavailable. Incomplete CI stamps remain ineligible.

Pages stores only the small site and metadata. IPAs stay in Releases and out of Git history.
See [Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) and
[release limits](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas).

Run `./test ToolsSnapshotTests --review` to check the site's image references.
The suite renders deterministic catalogs with the production site generator, then captures each page in an offline WebKit view.
It covers iPhone and iPad layouts in light and dark mode through the existing snapshot CI job.

## Archive locally

Supply `MATCH_PASSWORD` and use your own SSH access to Stuff-Signing.
From a clean checkout, run:

```bash
./Where/archive --output /tmp/where-build
```

The command downloads existing assets through Match and installs them in your local keychain and Xcode profile directory.
It does not need an Apple API key. It cannot create or renew signing assets.
For another registered app, use `./signing archive --app APP --output DIR`.

The output directory must not exist.
The command regenerates through `./ide --no-open`, archives optimized Debug, and exports `export/Where.ipa`.
Xcode logs remain under `logs/` in the output directory if the build fails.
The command does not upload the IPA.
Run `./ide --no-open` afterward to restore normal local signing settings.

The importable policies live in [`Tools/`](../Tools/README.md).
Their tests use fake processes and credentials. Complete the physical-device checks after configuring the signing secrets and Pages.
