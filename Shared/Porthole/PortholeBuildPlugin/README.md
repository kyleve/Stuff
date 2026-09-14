# PortholeBuildPlugin

This SwiftPM build plugin runs [PortholeGenerator](../PortholeGenerator/README.md) for an adopting Swift target.
The root [package manifest](../../../Package.swift) owns its target declaration.

The plugin declares every Swift source and local dependency source as a build input.
It emits only `PortholeGeneratedModule.swift` into the plugin work directory.
SwiftPM compiles the generated source into the adopting module. That file embeds the complete source archive and coverage document.
The plugin does not request a standalone catalog. SwiftPM copies non-Swift outputs as resources, which duplicates the embedded coverage across app and extension bundles.
Standalone generator invocations can request a separate report with `--catalog FILE`.

## Adoption

Add PortholeRuntime as a target dependency. Add PortholeBuildPlugin to the target's plugins.
Set `-Xfrontend -disable-access-control` and `-enable-private-imports` on the adopting target.
Run the matching normal-source guard with both flags removed. Preserve the target's normal compilation mode.
The plugin cannot set compiler flags or reconstruct the target's SDK and compilation conditions.
The application must install the generated module into its existing registry and scope.

The reusable plugin has no unsafe compiler flags. SwiftPM restricts dependency products that contain unsafe build settings.
Keep the flags on local adopting targets rather than the exported Porthole products.

## Validation

Generator tests cover optional report output and unchanged embedded source and coverage.
A clean integration build checks plugin execution, generated-source compilation, and the absence of copied `.porthole.json` resources.
The normal-source guard checks original access control with private call sites excluded.
