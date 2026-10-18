# InstallerKitUI

InstallerKitUI owns the reusable native update screen for InstallerKit.
See [README.md](README.md) and the [repository rules](../../AGENTS.md).

- Depend on InstallerKit, Broadway, SnapshotKit, and SFSafeSymbols. Never import an app module or persist update state here.
- Receive the host's process-owned `UpdateModel` and branding. Hosts own audience, demo, foreground, and navigation eligibility.
- Use InstallerKit's validated install URL and complete-history result. Preserve the last successful build beside a refresh failure.
- Derive shared failure text from the original error at this UI boundary. Show its diagnostic code; show the cached-data note only when a previous snapshot exists. Guard: `UpdateFailureDescriptionTests` and the page snapshots.
- Resolve browser routes by typed channel/build identity against the current model snapshot. Label manual notes as the selected release's predecessor delta; never present them as a comparison with the installed build.
- Show local revision status honestly and explain the Mac reinstall path. Never offer an in-app install action for a local binary that has not been published.
- Keep shared copy in this module's string catalog and appearance in `InstallerStylesheet`. Resolve styles below the screen's Broadway root.
- Use the section-decoration seam for host search anchors. Keep host-specific navigation and search types outside this module.
- Construct preview identities and catalogs with InstallerKit's typed Testing SPI. Inject them through the production service and model.

Run `./test InstallerKitUITests` and `./test InstallerKitUISnapshotTests --review`.
The update page and browser destinations own their shared image matrices; hosts cover branding and navigation wrappers.
