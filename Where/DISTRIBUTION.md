# Install Where Dev through GitHub

The [installer guide](../Tools/InstallerKit/README.md) covers adding apps to the common site.
GitHub Releases hosts signed IPAs. GitHub Pages hosts the install site, OTA manifests, and update catalog.
The [distribution workflow](../.github/workflows/where-distribution.yml) publishes these channels:

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
The repository must be public. Publication uses its built-in `GITHUB_TOKEN`; no additional hosting account or token is required.
The IPA, manifest, commit notes, and build metadata are public.
Apple's ad hoc profile still restricts installation to registered devices.
The provisioning profile inside the IPA includes those device identifiers.

1. In the Apple Developer account, register every phone that will install these builds.
   Create an Apple Distribution certificate and export its private key as a password-protected `.p12` file.
2. Create one **Ad Hoc** provisioning profile for each target below.
   Use the same team, distribution certificate, and registered devices for all three profiles.
   The checked-in [manifest](../Project.swift) owns the identifiers and entitlements.

   | Profile filename | Current app identifier | Capabilities |
   | --- | --- | --- |
   | `Where.mobileprovision` | `com.stuff.where.development` | Development App Group, iCloud, Push Notifications |
   | `WhereWidgets.mobileprovision` | `com.stuff.where.development.widgets` | Development App Group |
   | `WhereShareExtension.mobileprovision` | `com.stuff.where.development.share` | Development App Group |

   The Development App Group is `group.com.stuff.where.development`.
   The app's declared CloudKit container is `iCloud.com.stuff.where`.
   Include the manifest's capabilities even though these builds select the local store.
3. Add these repository secrets in GitHub Settings → Secrets and variables → Actions.
   Keep the original signing files outside the repository.

   | Secret | Value |
   | --- | --- |
   | `WHERE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` file |
   | `WHERE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for that file |
   | `WHERE_APP_PROFILE_BASE64` | Base64-encoded `Where.mobileprovision` |
   | `WHERE_WIDGET_PROFILE_BASE64` | Base64-encoded `WhereWidgets.mobileprovision` |
   | `WHERE_SHARE_PROFILE_BASE64` | Base64-encoded `WhereShareExtension.mobileprovision` |

   For example, on macOS:

   ```bash
   base64 -i /path/to/Where.mobileprovision | gh secret set WHERE_APP_PROFILE_BASE64
   ```

   Set passwords through GitHub's secret form or `gh secret set`'s interactive prompt.
4. In GitHub Settings → Actions → Policies, allow this workflow's `push`, `workflow_dispatch`, and `pull_request_target` events.
   Scope the event policy to `.github/workflows/where-distribution.yml`.
   GitHub's default policy can block `pull_request_target` in public repositories.
   See [workflow execution policies](https://docs.github.com/en/actions/how-tos/administer/control-workflow-execution).
5. In GitHub Settings → Pages, select **GitHub Actions** as the publishing source.
   Allow `workflow_dispatch` for `.github/workflows/installer-pages.yml` in the Actions event policy.
   The default feed URL is `https://kyleve.github.io/Stuff/updates.json`.
   If Pages uses a custom domain, set `INSTALLER_FEED_URL` to its HTTPS catalog URL before building.
6. Create the repository label `installable` if it does not exist.
   Merge the integration into `main`, then set `WHERE_DISTRIBUTION_ENABLED` to `true`.
   Run **Where Dev Distribution** manually on `main` to publish the first build.
   Open its install link on a registered phone and verify launch, widgets, and sharing.
   Add `installable` to an open PR, then push again to verify that its page updates.

Adding a device requires refreshed profiles for all three targets and a new build.
Replace the profile secrets before they expire.
Renew the certificate and profiles together when the signing certificate expires.
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
Use an isolated macOS runner for each archive job.

The archive job uses a temporary keychain and removes its signing files after the job.
It validates each profile's expiry, device list, team, and generated target settings before archiving.
It signs the app and both extensions during the archive, then exports with Xcode's `release-testing` method.
This is Xcode's current name for ad hoc export.
The archive job has no repository write token.

The publication job uses control scripts from `main` and a repository write token.
It validates the IPA's Development identity, build configuration, commit stamp, bundle version, and signing resources.
It checks the live branch SHA, PR label, and merge conflicts before publication.
Retirement checks the live label and PR state, even when conflicts exist.
Runs for one channel are serialized. Stale events cannot replace newer catalog entries or retire a newly relabeled channel.
A conflict or failed archive leaves the previous hosted build available.
Publication does not wait for the separate test workflows.

Each archive gets a distinct prerelease: `installer-where-<channel>-<run>-<attempt>`.
The publisher uploads `app.ipa` to a draft, validates its SHA-256 digest and size, then publishes it.
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
Rerun the failed publication job to retry the catalog write with the existing archive.
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

## Archive locally

Install the distribution identity in your keychain and the three profiles in Xcode first.
Keep copies of the profiles together under the filenames listed above.
From a clean checkout, run:

```bash
./Where/archive --profiles /path/to/profiles --output /tmp/where-build
```

The output directory must not exist.
The command regenerates through `./ide --no-open`, archives optimized Debug, and exports `export/Where.ipa`.
Build and export logs remain in the output directory if Xcode fails.
The command does not upload the IPA.
Run `./ide --no-open` afterward to restore normal local signing settings.

The importable policies live in [`Tools/`](../Tools/README.md).
Their tests use fake processes and credentials. Complete the physical-device checks after configuring the signing secrets and Pages.
