# InstallerKitUI

InstallerKitUI provides a native update page with app artwork, build details, install actions, and incoming commits.
The screen adapts to light and dark appearance, Dynamic Type, and iPad widths.
InstallerKit remains the Foundation-only engine.

## Integration

Link the `InstallerKitUI` package product. Inject the same `UpdateModel` that drives the host's update badge.

```swift
AppUpdatesView(
    model: updates,
    branding: AppUpdateBranding(
        name: "Example Dev",
        subtitle: "Your app's description",
        icon: Image("AppIconPreview")
    )
)
```

The host supplies localized branding and an optional image. A missing image shows the app's initial.
The page seeds its own Broadway root and supplies a navigation title.
Place it in the host's navigation stack. Hosts retain audience, demo, and foreground gates.

The page checks on appearance, supports pull-to-refresh, and offers a manual check.
InstallerKit owns throttling, cancellation, cache persistence, and release selection.
Offline state keeps the last successful result visible. Retired branches can offer that app's main build.
Older feeds omit build details and show “Not recorded” instead of inferred values.

Hosts can pass `sectionDecoration` to attach search anchors or highlight modifiers to `.check` and `.changes`.
The modifier applies to each complete section. No host navigation types enter this module.

## Switching builds

Open **Other Builds** near the top of the page. The sheet lists Main, then active PR channels for the installed app.
The installed channel has a badge. Each channel opens its latest build.
Choose **Install This Build** for any build other than the installed one.
**Build History** lists retained builds, including older versions, and marks the exact installed build.

Browsing does not change the host's update badge or automatic update channel.
After installation, the new app's signed identity determines its update channel.

Local builds show **Local**, their recorded commit and working-tree status, and the same remote build browser.
They have no CI run number or automatic update badge. Missing Git information shows **Not recorded**.
The browser also explains how to return to Local: install again from Xcode or the app's Mac installer.
Local binaries stay on the Mac; the browser does not offer a remote Local download.
Build details resolve against the current catalog. If a refresh retires a channel or removes a build, its install action disappears.
Manual build notes describe that release's changes since its own predecessor. They do not compare branches with the installed build.

## Tests

The shared previews construct typed InstallerKit fixtures through its DEBUG Testing SPI.
`InstallerPreview.catalog(_:)` returns a catalog synchronously. `localBuild(revision:)` accepts a typed clean, dirty, or unavailable revision.
Previews inject these fixtures into the production service and model, which retain catalog validation.

`./test InstallerKitUITests` checks stylesheet traits, root resolution, and hosted navigation.
`./test InstallerKitUISnapshotTests --review` covers shared screen states without Where.
