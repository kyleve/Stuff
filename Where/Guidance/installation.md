# Device installation

## Installing to a device

`./Where/install` builds, signs, and installs the app onto a connected iPhone
from the CLI — macOS-only, one-time `./ide --team-id <id>` setup. It defaults
to the **Where Development** scheme with compiler optimizations forced on, so
DEBUG-only developer surfaces survive at near-Release speed. Pass
`--configuration Beta` for the TestFlight-style production identity or
`--configuration Release` for the App Store audience. Options:
`./Where/install --help`.

`./Where/archive` exports the same optimized Development audience for ad hoc
distribution. [DISTRIBUTION.md](../DISTRIBUTION.md) owns account setup and operation.
Keep CI profile overrides scoped to the Development device configuration in
`Project.swift`; validate all three profiles against generated target settings
before archiving. Sign the app and extensions during archive, not only export.
Shared publication rules live in [Tools/InstallerKit/AGENTS.md](../../Tools/InstallerKit/AGENTS.md#publication).
Where's archive and signing guards are `Tools/Tests/test_signing_profiles.py`,
`test_where_archive.py`, and `test_where_signing_command.py`.
