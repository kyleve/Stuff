# InstallerKit

InstallerKit checks for ad hoc iOS updates from the repository's shared install site.
It has no dependency on Where, SwiftUI, or UIKit.
[InstallerKitUI](../InstallerKitUI/README.md) supplies the reusable native update page. Each app supplies branding, navigation, and its badge.

## Integration

Link the `InstallerKit` package product. At the app composition root, read the signed
`InstalledBuild` metadata and create one `UpdateService` and `UpdateModel`.
The host controls which build audiences and foreground surfaces may check for updates.

```swift
let client = UpdateClient(session: URLSession(configuration: .ephemeral))
let service = UpdateService(
    installed: installed,
    preferences: preferences,
    client: client,
    now: Date.init
)
let updates = UpdateModel(service: service)
```

`preferences` conforms to `UpdatePreferencesStoring` and stores one device-local
`UpdatePreferences` value. Report corrupt storage before returning an empty cache.
Where's adapter is `WherePreferences.installerUpdates`.

Call `await updates.refresh(force: false)` when an eligible foreground surface becomes active.
Use `force: true` for a manual check. Bind badges to `needsAttention` and render `state`.
Failure state retains both the original error and the last successful snapshot.
`UpdateClient.FetchError.httpStatus` carries the server's HTTP status code.
Other response failures distinguish unexpected server locations, non-HTTP responses, and oversized feeds.
The service treats `URLError.cancelled` as cancellation, even when the calling Swift task remains active.
Cancellation restores the previous model state and preserves the cached catalog and check date. A later manual check can retry immediately.
Other transport, decoding, and catalog validation errors keep their original types. The UI owns localized failure text.
Use a release's `installURL` for installation and `installed.commitURL(for:)` for commit links.

Each service snapshot also exposes `browser`, an `UpdateBuildBrowser` for the installed app.
It lists active channels with main first, then PRs by their latest build. Channels include retained build history.
Resolve a typed `Selection(channel:build:)` against the current browser before showing an install action.
Selections can target older builds. Retired or pruned selections no longer resolve.
Browsing does not change update notifications; the next installed app's signed identity determines its channel.
Selected build notes describe that release's own predecessor delta, not a comparison across branches.

## Identity and catalog

`Tools/InstallerKit/stamp-installer-info.sh` writes the generic `Installer*` Info.plist keys before signing.
`InstalledBuild` requires an app ID, bundle identifier, repository URL, and HTTPS feed URL.
Its `source` distinguishes `.local(LocalRevision)` from `.published(Publication)`.
Published identity requires a clean commit, channel, run, and attempt. `publication` exposes those coupled values when present.
Local identity requires the explicit `InstallerChannel = local` stamp. Its revision can be clean, dirty, or unavailable.
Missing or malformed published metadata never falls back to Local.

Configure the Development target's default `INSTALLER_APP_ID`, `INSTALLER_REPOSITORY_URL`, and `INSTALLER_FEED_URL`, with `INSTALLER_CHANNEL = local`.
CI overrides those settings with its publication identity. The stamp clears old run and attempt values on local rebuilds.
Local builds can browse and install remote releases, but receive no automatic update or retirement badge.
They do not appear in the public catalog. Reinstall through Xcode or the host's local installer to return to Local.
The cache stores the catalog, so each newly installed build evaluates it against its own identity.
The host must also gate its permitted audience, tests, demo mode, and headless launches.

Schema 3 contains `apps`, each with `id`, `name`, `bundleIdentifier`, and `channels`.
The catalog rejects duplicate identities and manifests outside their exact build paths.
Channels and retirement fallback never cross app or bundle identities.
Successful automatic checks are cached for one hour. Manual checks always fetch.
Incoming notes span skipped releases when their commit ancestry remains connected.
Releases can carry optional `buildDetails` from the signed IPA: version, minimum iOS version, and download size.
The decoder accepts older releases without this block and validates present values before caching them.
PR releases can also carry an optional `pullRequestTitle`, recorded from GitHub at publication time.
Older releases omit the title. Channel and build identities do not depend on this display text.

Publication and app registration are documented in [the installer guide](../../Tools/InstallerKit/README.md).
The existing Where integration lives in `RegularApplicationRuntime` and `DevelopmentUpdatesView`.

## Tests

Debug builds expose typed fixture initializers through `@_spi(Testing) import InstallerKit`.
Previews can construct installed identities and catalogs directly, then inject them through the existing service dependencies.
Production callers still read signed metadata and decode catalogs. Services validate catalogs before use.

Run `./test InstallerKitTests` for identity, catalog, request, cache, and cancellation coverage.
InstallerKitUI owns the shared screen snapshots. WhereUI covers its Settings integration.
`ToolsSnapshotTests` captures the shared download site.
