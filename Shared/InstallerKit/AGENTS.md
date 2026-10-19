# InstallerKit

InstallerKit owns app-neutral ad hoc update identity, catalog validation,
fetching, cache policy, and observable presentation state. See [README.md](README.md).
The [repository rules](../../AGENTS.md) apply.

- Depend only on Foundation, Observation, and PeriscopeCore. Never import app
  modules, InstallerKitUI, SwiftUI, or UIKit. Hosts own audience gates, storage, and lifecycle.
  InstallerKitUI owns reusable native presentation and its copy.
- Construct one service and model in the host composition root. Inject device-local
  `UpdatePreferencesStoring` and `UpdateFetching` dependencies.
- Keep direct fixture initializers behind the DEBUG Testing SPI. Production callers use signed metadata and decoded catalogs.
- Select channels by both app ID and bundle identifier. Retirement can offer only
  that app's main build. Pin manifest URLs to the signed feed, app, channel, run, and attempt.
- Manual browsing includes only that app's active channels and retained releases. Resolve channel/build selections against the latest snapshot; browsing must not change the installed identity or update badge. Guard: `UpdateBuildBrowserTests`.
- Require an explicit local stamp for locally controlled builds. Preserve clean, dirty, and unavailable revisions without inventing a CI identity. Malformed publication stamps must not become Local. Guard: `InstalledBuildTests`.
- Local builds can browse published channels but must not receive automatic update badges or appear as published releases. Re-evaluate cached catalogs against the installed source. Guards: `UpdateBuildBrowserTests`, `UpdateServiceTests`.
- Order releases by run and attempt. Never order commit hashes or marketing versions.
  Show complete notes only when every retained predecessor connects to the installed revision.
- Keep signed build details optional for older feeds. Validate present metadata before caching or presenting it.
- Cache reuse must not supersede a network request. Cancelled or superseded reads
  must not replace the last successful catalog or model state.
- Preserve HTTP status codes and distinguish response-policy failures. Pass transport and feed errors through to the UI reporting boundary. Guard: `UpdateClientTests`.

Guards: `UpdateCatalogTests`, `UpdateServiceTests`, and `UpdateModelTests`.
Run `./test InstallerKitTests`. InstallerKitUI owns the shared image matrix; hosts cover their integration.
