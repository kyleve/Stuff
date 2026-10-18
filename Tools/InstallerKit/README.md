# Shared iOS installer

All registered iOS apps use one GitHub Pages site and one `updates.json` catalog.
GitHub Releases stores the signed IPAs. InstallerKit supplies the in-app update engine.
InstallerKitUI supplies the reusable native update page.
Each app owns its signing configuration, archive command, audience gate, branding, and Settings navigation.

The homepage shows only the latest successful `main` build for each app.
`/apps/<app-id>/` lists that app's PR builds.
`/apps/<app-id>/<channel>/` shows a build's install action and incoming commits.
Apps appear after their first publication or retirement receipt.
App cards show their icon, version, download size, and publication date.
Build pages add the minimum iOS version, source commit, workflow run, bundle ID, and release notes.

## Add an app

1. Add the app to [`.github/installer-apps.json`](../../.github/installer-apps.json).
   Use a stable lowercase app ID and a unique Development bundle identifier.
   Declare its IPA app path, signed app and extension paths, and required Info.plist values.
   The trusted controller uses this registration to validate the exported IPA.
   To add artwork, set `site.subtitle` and `site.icon` in that registration.
   Use a repository-relative PNG path. Optionally add `site.darkIcon` for dark appearance.
   The Pages job copies these assets from trusted `main`; it does not read artwork from the PR.
   Apps without artwork use their first letter. A registered file that is missing fails the site build.
2. Link [InstallerKit](../../Shared/InstallerKit/README.md) and implement `UpdatePreferencesStoring` with device-local storage.
   Construct one `UpdateService` and `UpdateModel` at the composition root.
   Gate permitted audiences, tests, demo mode, and foreground requests in the host.
   Bind the Settings badge to `needsAttention`.
   Link [InstallerKitUI](../../Shared/InstallerKitUI/README.md) and present `AppUpdatesView(model:branding:)` in the app's navigation stack.
   Supply an `AppUpdateBranding` with the localized name, subtitle, and an optional icon from the app's asset bundle.
   Custom presentations can render `state` and use the validated `installURL` directly.
3. Call `bash "$SRCROOT/Tools/InstallerKit/stamp-installer-info.sh"` in a post-build phase before signing.
   Disable dependency analysis and user-script sandboxing for that phase.
   Pass these build settings through the archive command:

   | Build setting | Source |
   | --- | --- |
   | `INSTALLER_APP_ID` | Registered app ID |
   | `INSTALLER_REPOSITORY_URL` | `https://github.com/$GITHUB_REPOSITORY` |
   | `INSTALLER_CHANNEL` | Controller output: `main` or `pr-<number>` |
   | `INSTALLER_RUN` | `GITHUB_RUN_ID` |
   | `INSTALLER_ATTEMPT` | Archive job's `GITHUB_RUN_ATTEMPT` |
   | `INSTALLER_FEED_URL` | Shared catalog URL |

   Set the Development target's defaults for app ID, repository URL, and feed URL, with `INSTALLER_CHANNEL = local`.
   The CI archive command overrides those defaults with the publication metadata above.
   Local builds need no run or attempt; they can browse remote builds without automatic update badges.
   Keep local binaries out of the public catalog. Users return to Local through Xcode or the app's Mac installer.
   The script reads the commit and clean status from Git. Missing values become `unknown`.
   `InstalledBuild` also reads the actual `CFBundleIdentifier` from the signed bundle.
4. Add an app-specific distribution workflow using [Where's wrapper](../../.github/workflows/where-distribution.yml) as the template.
   Change its app ID, archive command, signing context, artifact path, enable variable, and concurrency prefix.
   Retain the trusted-main plan and publisher jobs, archive credential restrictions, and cleanup step.
   The current CircleCI archive job supports Where. Add an explicit registered job before enabling another app.
   Keep CircleCI configuration and control scripts on `main`. Use the existing pinned macOS executor.
   Keep the CircleCI API token on the GitHub controller. Store signing secrets only in the restricted CircleCI context.
   From the repository root, use `python3 -m Tools.InstallerKit.installer_distribution plan --app <id>` and the matching `finish` command.
   Pass the successful receipt to `installer_update_feed.py`.
   Keep the archive attempt output when retrying only the publisher.
5. Merge the registration, workflow, and app integration into `main` before enabling the app's workflow.
   Configure signing and registered devices for that app. Publish a main build and verify installation on a physical device.
   Then add `installable` to a same-repository PR and verify its build and update flow.

[Where's setup guide](../../Where/DISTRIBUTION.md) lists its signing secrets and device checks.
New apps reuse publication and update logic. They do not need another site or a copy of the Swift engine.

## Shared hosting

Select **GitHub Actions** as the Pages source. Allow `workflow_dispatch` for
[installer-pages.yml](../../.github/workflows/installer-pages.yml) in the repository's Actions event policy.
The repository must be public for credential-free IPA downloads.

The default feed is `https://<owner>.github.io/<repository>/updates.json`.
Set the repository variable `INSTALLER_FEED_URL` before archiving when using a custom domain.
Every app workflow and local Development target must use that same URL.
Update the target's default feed setting when selecting a custom domain.
The signed URL fixes an installed build's update location.

`installer_update_feed.py` writes the shared catalog to `installer-update-feed` with compare-and-swap retries.
A concurrent writer reloads the catalog before merging its own app and channel.
It then dispatches **App Install Site** on `main`.
That workflow reads the latest complete catalog and deploys all pages and manifests together.
It has one deployment concurrency group for all apps.

## Publication contract

The `installable` label opts a same-repository PR into every enabled app distribution workflow.
It authorizes signing that branch's code, including later commits. Fork PRs are excluded.
The controller runs from `main` through `pull_request_target`, including when a PR has merge conflicts.
CircleCI archives the selected commit, while GitHub publishes the returned IPA.
The handoff verifies the successful pipeline, job, artifact path, and signed build identity.
The label trusts branch build code with the signing identity. A temporary keychain does not isolate secrets from that code.
Conflicts fail the installable build before signing. Removing the label or closing the PR still retires its channels.

Serialize each app's channel mutations. Recheck the live head, label, state, and mergeability before publication.
A failed build preserves the previous successful build. Retirement removes install manifests but retains history.
Historical GitHub assets remain available. Retirement cannot revoke an installed IPA or cached manifest.

Release tags use `installer-<app-id>-<channel>-<run>-<attempt>` and contain one `app.ipa` asset.
The publisher verifies the uploaded asset's URL, size, and SHA-256 digest before publishing its draft.
Retries reuse matching assets. Published bytes are never replaced.
Tags anchor to trusted `main`; the release notes and signed stamp identify the actual source commit.

The catalog uses schema 3: `apps[]` contains `id`, `name`, `bundleIdentifier`, and `channels[]`.
Manifest paths are `manifests/<app-id>/<channel>/<run>-<attempt>.plist`.
App IDs and bundle identifiers must be unique. An existing app ID cannot change its bundle identifier.
Retirement fallback stays within that app. Releases are ordered by run and attempt.
Each channel retains 100 releases. Missing or rewritten ancestry produces explicit incomplete-history states.

New releases include `buildDetails`: marketing `version`, `minimumOSVersion`, and IPA `sizeBytes`.
The publisher reads the versions from the signed Info.plist and measures the exported IPA before upload.
Older releases can omit this block. Display code must keep missing details explicit.

Schema 3 replaces the unreleased Where-only catalog. No schema 2 deployment or installed-client migration is supported.
Enable distribution only after the matching app and controller changes are on `main`.

## Validation

Run `python3 -m unittest discover -s Tools/Tests -p 'test_installer*.py'` for publication and site policy.
Run `python3 -m unittest discover -s Tools/Tests -p 'test_github_*.py'` for transport and verified releases.
Run `./test InstallerKitTests InstallerKitUITests` for the Swift engine and native styling.
Run `./test InstallerKitUISnapshotTests ToolsSnapshotTests --review` for native and site images.
The site fixtures include two apps, matching PR numbers, main-only browsing, retirement, and empty states.
They also cover long names, missing artwork, and older builds without display metadata.
The second app is synthetic. Real signing, installation, and update confirmation require a registered device.
