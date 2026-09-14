# WhereAssets

WhereAssets owns the compiled app-icon preview catalog. Import `WhereAssets`
and pass `WhereAssetBundle.bundle` to image loading APIs.

The catalog stays at `WhereUI/Sources/Resources/AppIconPreviews.xcassets`.
Run `./icons` to change it. The package target shares the `Where` ancestor and
selects its source and resource inputs explicitly. Other Where files are excluded.

Xcode emits a private `resourceBundle` into both asset and string symbol files.
Porthole's private-access compiler flags make those names conflict in one module.
This resource boundary keeps asset symbols separate from WhereUI's string symbols.
It preserves stock generation without rewriting generated files or catalog contents.

The module imports Foundation only and opens no stores, connections, or listeners.
Its generated Porthole catalog is installed with the rest of Where's process graph.
Run `./test WhereAssetsTests` to verify the compiled resource bundle.
