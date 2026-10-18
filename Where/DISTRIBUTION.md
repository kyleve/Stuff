# Archive Where Dev for ad hoc installation

The archive command signs optimized Where Development and both app extensions.
It validates the profiles and generated target settings before the archive.

## Archive locally

Install the distribution identity in your keychain and the three profiles in Xcode first.
Keep copies named `Where.mobileprovision`, `WhereWidgets.mobileprovision`, and `WhereShareExtension.mobileprovision` together.
All three must be unexpired Ad Hoc profiles for the same team, certificate, and registered devices.
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
Their tests use fake processes and credentials. Verify the exported app and its extensions on a registered physical device.
