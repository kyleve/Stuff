# Shared iOS installer

All registered iOS apps use one GitHub Pages site and one `updates.json` catalog.
GitHub Releases stores the signed IPAs. InstallerKit supplies the in-app update engine.
InstallerKitUI supplies the reusable native update page.
Each app selects its signing configuration, audience gate, branding, and Settings navigation.
The shared `./signing` command owns Match maintenance and Fastlane archives.
Local maintenance renews expired certificates and regenerates profiles. Archives only download existing assets.
Register the scheme, configuration, targets, and profile override keys in `.github/installer-signing-apps.json` in the trusted checkout.
Bundle identifiers come from generated Xcode settings, not the descriptor.
See [Where setup](../../Where/DISTRIBUTION.md#one-time-setup) for the shared signing repository and Apple account checklist.

The homepage shows only the latest successful `main` build for each app.
`/apps/<app-id>/` lists that app's PR builds.
`/apps/<app-id>/<channel>/` shows a build's install action and incoming commits.
Apps appear after their first publication or retirement receipt.
App cards show their icon, version, download size, and publication date.
Build pages add the minimum iOS version, source commit, workflow run, bundle ID, and release notes.

The same Pages deployment includes [Flyover atlases](../../Shared/Flyover/README.md#daily-web-publication) under `/flyover/`.
CircleCI passes each build to its publisher through the workflow workspace.
InstallerKit retains its signed-IPA validation and publication policy. Flyover uses a separate unsigned capture workflow.

## CI cleanup failures

Cleanup attempts search-list restoration, temporary keychain deletion, and owned-profile removal independently. A failure makes the job fail and retains the ownership and recovery files for a retry. It does not delete unexpected profiles or a directory whose ownership changed.

A failed deletion can leave signing credentials on that job's isolated runner until the runner is destroyed. Recovery files must not be uploaded as artifacts. Do not reuse a runner after failed cleanup. The lifecycle wrapper uses the pinned Ruby and the trusted checkout’s frozen bundle through `mise exec -- bundle exec ruby`. CI installs this bundle before preparing signing material. Cleanup before any signing state exists succeeds without loading Ruby.

## Add an app

After the shared Apple account and CI setup, each app has five setup phases.
The in-app update page is optional and can be added separately.

1. **Register the app.** Check that the distribution team has an explicit Apple App ID for the host and each extension.
   Match each identifier to its target's bundle identifier in `Project.swift`.
   Check the capabilities and required App Group or iCloud container associations against the target's entitlements.
   Xcode automatic signing can create these registrations. Reuse matching registrations; do not create duplicates.
   If an identifier or capability is missing, configure it in Xcode or [Apple Developer](https://developer.apple.com/help/account/identifiers/register-an-app-id/).
   A local install alone does not prove that every explicit identifier exists; development signing can use a wildcard App ID.
   Add the app to [`.github/installer-apps.json`](../../.github/installer-apps.json).
   Use a stable lowercase app ID and a unique Development bundle identifier.
   Declare its IPA app path, signed app and extension paths, and required Info.plist values.
   The trusted controller uses this registration to validate the exported IPA.
   Register its scheme, configuration, product, targets, and profile override keys in `.github/installer-signing-apps.json`.
   The product must match the registered app bundle name.
   For apps that exist only on a PR branch, set `sourceDirectory` to their top-level source directory.
   The controller skips publication when that directory is absent from the selected commit. Retirement still runs.
   For artwork, set `site.subtitle` and `site.icon`; optionally add `site.darkIcon`.
   Use repository-relative PNG paths that already exist on trusted `main`.
   Apps without artwork use their first letter. Missing registered artwork fails the site build.
2. **Integrate the app target.** Add ad hoc profile overrides for each signed target in `Project.swift`.
   Call `bash "$SRCROOT/Tools/InstallerKit/stamp-installer-info.sh"` in a post-build phase before signing.
   Disable dependency analysis and user-script sandboxing for that phase.
   Configure these build settings:

   | Build setting | Source |
   | --- | --- |
   | `INSTALLER_APP_ID` | Registered app ID |
   | `INSTALLER_REPOSITORY_URL` | Registered GitHub repository URL |
   | `INSTALLER_CHANNEL` | Controller output: `main` or `pr-<number>` |
   | `INSTALLER_RUN` | Publication plan's epoch-millisecond run ID |
   | `INSTALLER_ATTEMPT` | CircleCI pipeline number |
   | `INSTALLER_FEED_URL` | Shared catalog URL |

   Set Development defaults for app ID, repository URL, and feed URL, with `INSTALLER_CHANNEL = local`.
   The CI archive command overrides those defaults with publication metadata.
   Local builds need no run or attempt. They can browse remote builds without automatic update badges.
   Keep local binaries out of the public catalog. Return to Local through Xcode or the app's Mac installer.
   The stamp reads the commit and clean status from Git. Missing values become `unknown`.
   `InstalledBuild` also reads the actual `CFBundleIdentifier` from the signed bundle.
3. **Merge the configuration.** Merge both registrations and the shared controller into `main`.
   The app source can remain on its PR branch if the registration declares `sourceDirectory`.
   The source selected for signing must contain the target integration from phase 2.
4. **Prepare signing and enable distribution.** Run `./signing setup --app <id>` as described below.
   This refreshes signing profiles, then sets the app's CircleCI project variable.
5. **Publish and verify.** Add `installable` to a same-repository PR, or run `python3 -m Tools.ci_request installer` for `main`.
   Open the published install link on a registered device and verify the app.

CircleCI selects enabled registrations from trusted `main` and generates one native job group for each app/channel.
Signing secrets stay in `where-distribution-signing`; GitHub write credentials stay in `github-publication` on Linux.
The selected source supplies build code, but never the signing descriptor, Fastfile, Gemfile, or controller.
[CI operation](../../.circleci/README.md) owns context restrictions, webhook setup, scheduling, and migration activation.

[Where's setup guide](../../Where/DISTRIBUTION.md) lists its signing secrets and device checks.
New apps reuse publication and update logic. They do not need another site or a copy of the Swift engine.

## Website development

[The Astro project](Site/README.md) contains the Astro templates and local preview commands.
Python owns catalog validation and install manifests. Astro renders the pages from validated input.
Local previews and WebKit snapshots share deterministic catalogs and the production templates.
WebKit retains every page state at phone baseline. Index, app, and channel layouts
cover both appearances and tablet; selected status pages add dark or tablet checks.

## Shared hosting

Keep **GitHub Actions** as the Pages source.
Allow `repository_dispatch` for [installer-pages.yml](../../.github/workflows/installer-pages.yml).
That small bridge uploads the complete site from the exact generated commit and reports deployment status.
The repository must be public for credential-free IPA downloads.

CircleCI builds the site independently of signing and app enablement.
Before the publication branch exists, it deploys an empty schema-3 catalog.
Request an initial or replacement deployment with `python3 -m Tools.ci_request pages`.

The default feed is `https://<owner>.github.io/<repository>/updates.json`.
For a custom domain, set CircleCI project variable `INSTALLER_FEED_URL` before archiving.
Use that same URL in local Development targets. The signed URL fixes an installed build's update location.

`installer_update_feed.py` writes the catalog to `installer-update-feed` with compare-and-swap retries.
Native publication jobs then request site deployment. A concurrent writer reloads the catalog before changing its own channel.
`ci_pages.py` builds from fresh `main`, reads the complete catalog, and combines the latest verified Flyover bundle.
A lease protects its generated `gh-pages` branch. The Pages Action deploys that exact commit.
Unreadable or invalid catalogs preserve the previous site, including a missing file on an existing catalog branch.
Local previews can still use `installer_update_site --catalog <path>`.

## Publication contract

The `installable` label opts a same-repository PR into every enabled app distribution workflow.
It authorizes signing that branch's code, including later commits. Fork PRs are excluded.
The fixed-main custom webhook runs even when a PR has merge conflicts.
CircleCI archives the selected commit and publishes its verified workspace IPA from a separate Linux job.
Publication requires a successful archive and matching signed build identity.
The label trusts branch build code with the signing identity. A temporary keychain does not isolate secrets from that code.
Conflicts fail the installable build before signing. Removing the label or closing the PR still retires its channels.

To rebuild an already labeled PR, run:

```bash
python3 -m Tools.ci_request installer --pr 295
```

Manual PR requests use the live head and retain the same eligibility checks and per-app concurrency groups.
Planning selects the source commit once. Publication validates the IPA against that commit.
If the PR advances or loses eligibility, publication skips the build.
Omit `--pr` to publish `main`.

Serialize each app's channel mutations. Recheck the live head, label, state, and mergeability before publication.
A failed build preserves the previous successful build. Retirement removes install manifests but retains history.
Historical GitHub assets remain available. Retirement cannot revoke an installed IPA or cached manifest.

Before archiving, the controller records optional channel `buildStatus` metadata and requests a Pages deployment.
It contains `state` (`preparing` or `failed`), the run/attempt `id`, and the source `sha`.
Status writes recheck the live head and PR eligibility. They cannot grant installability or replace a newer attempt's status.
The previous published release remains installable while a replacement builds or fails.
Successful publication clears matching or older progress. Retirement clears progress and disables installs.
An inactive channel without releases or progress shows **No build yet**, rather than claiming a build was retired.
Optional `workflowURL` metadata links new status pages and clients to CircleCI. Historical builds retain their GitHub links. Refresh after its Pages deployment to see the new state.
If the status job or Pages deployment cannot finish, the previously deployed page remains visible.
Existing native clients ignore this optional metadata and continue to use `active` and retained releases.

Release tags use `installer-<app-id>-<channel>-<run>-<attempt>` and contain one `app.ipa` asset.
The publisher verifies the uploaded asset's URL, size, and SHA-256 digest before publishing its draft.
Draft assets can use a temporary `untagged-…` URL under the same repository.
After publication, the publisher verifies the same asset's identity, size, digest, and final tag URL before returning its install URL.
A publisher retry reuses matching assets. Rebuilds require a new pipeline; rerunning all jobs retains the old immutable identity.
Published bytes are never replaced. Canceling a complete workflow can leave progress pending until the next publication.
Tags anchor to trusted `main`; the release notes and signed stamp identify the actual source commit.

The catalog uses schema 3: `apps[]` contains `id`, `name`, `bundleIdentifier`, and `channels[]`.
Manifest paths are `manifests/<app-id>/<channel>/<run>-<attempt>.plist`.
App IDs and bundle identifiers must be unique. An existing app ID cannot change its bundle identifier.
Retirement fallback stays within that app. Releases are ordered by run and attempt.
Each channel retains 100 releases. Missing or rewritten ancestry produces explicit incomplete-history states.

New releases include `buildDetails`: marketing `version`, `minimumOSVersion`, and IPA `sizeBytes`.
The publisher reads the versions from the signed Info.plist and measures the exported IPA before upload.
Older releases can omit this block. Display code must keep missing details explicit.
New PR releases also record `pullRequestTitle` from live GitHub metadata when the feed is published.
Title edits appear with the next publication. Historical releases keep their recorded titles; older releases can omit them.
The native Other Builds list uses this text without changing the channel's identity or install destination.

Schema 3 replaces the unreleased Where-only catalog. No schema 2 deployment or installed-client migration is supported.
Enable distribution after the controller registration is on `main` and the selected app source includes signing overrides and the installer stamp.

## Validation

Run `python3 -m unittest discover -s Tools/Tests -p 'test_installer*.py'` for publication and site policy.
Run `python3 -m unittest discover -s Tools/Tests -p 'test_github_*.py'` for transport and verified releases.
Run `./test InstallerKitTests InstallerKitUITests` for the Swift engine and native styling.
Run `./test InstallerKitUISnapshotTests ToolsSnapshotTests --review` for native and site images.
The site fixtures include two apps, matching PR numbers, main-only browsing, retirement, and empty states.
They also cover long names, missing artwork, and older builds without display metadata.
The second app is synthetic. Real signing, installation, and update confirmation require a registered device.
