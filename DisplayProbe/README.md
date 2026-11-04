# DisplayProbe

DisplayProbe shows live display measurements from the app's active window and screen.
It uses public UIKit APIs and requires iOS 27 or later.

## Use

1. Open DisplayProbe on the device.
2. Read the screen points, native pixels, rendering scale, and native scale.
3. Tap **Save reading** before you fold or rotate the device.
4. Change the device position, then save another reading with a descriptive label.
5. Tap **Grid** to see the app's full drawable area with a 100-point grid.
6. Tap **Share** to export the current and saved readings as text.

Saved readings remain in memory for the current session. They are not stored on disk.

## Measurement contract

The screen comes from `window.windowScene.screen`. Screen bounds, scene bounds, window bounds,
and safe-area insets are separate measurements. A window can occupy less space than the screen.

`nativeBounds` reports pixels in UIKit's native coordinate space. Rotation can change the
orientation of the screen and window bounds without changing the order of the native dimensions.
`scale` and `nativeScale` can differ. The app shows both without substituting one for the other.

The grid measures its full view, including unsafe edges. The controls stay inside the safe area.
The center line marks the mathematical midpoint. It does not identify a physical hinge.
The app cannot enumerate inactive physical panels that UIKit does not expose to its scene.

## Build and install

Run `./ide --no-open` from the repository root to generate the workspace.
Use the **DisplayProbe** scheme for a simulator or a signed physical-device build.
Configure the developer team with `./ide --team-id <TEAM_ID> --no-open` when necessary.

```sh
mise exec -- xcodebuild build -workspace Stuff.xcworkspace \
  -scheme DisplayProbe -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData/DisplayProbe -allowProvisioningUpdates

xcrun devicectl device install app --device <DEVICE_ID> \
  DerivedData/DisplayProbe/Build/Products/Debug-iphoneos/DisplayProbe.app
xcrun devicectl device process launch --device <DEVICE_ID> com.stuff.displayprobe
```

The app has no account, network connection, entitlements, or third-party libraries.
The source files in `Sources/` own capture, presentation, and the grid.
Run `./test DisplayProbeTests` for measurement and export regression coverage.
