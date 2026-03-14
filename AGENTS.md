# Stuff – Repository Shape

## Build system

| Tool  | Version | Pinned via   |
|-------|---------|--------------|
| Tuist | 4.40.0  | `.mise.toml` |

Tuist manifests live at the repo root (`Project.swift`, `Tuist.swift`).
Run `./ide` (or `./ide -i` to also install dependencies) to regenerate the
Xcode project.

## Targets

| Target             | Type       | Bundle ID                      | Platforms                  |
|--------------------|------------|--------------------------------|----------------------------|
| PhotoFramer        | Mobile App | com.stuff.photo-framer         | iPhone, iPad, Mac Catalyst |
| PhotoFramerTests   | Unit Tests | com.stuff.photo-framer.tests   | iPhone, iPad, Mac Catalyst |

Add more targets to `Project.swift` using `mobileApp()`, `macApp()`, or `framework()` helpers.

### PhotoFramer

Photo framing app — import photos from the library, file picker, or drag-and-drop,
then crop-to-fill or fit-with-mat to standard print (4×6, 5×7, 8×10, 11×14) and
social (1:1, 4:5, 16:9, 9:16) sizes. Export to photo library or file system.

Architecture: `@Observable` view model → stateless `FramingService` (pure CGImage
operations) → `PhotoExporter` for I/O. SwiftUI throughout; uses `PhotosPicker` and
`.fileImporter()` (no UIKit bridges for pickers).

## Deployment

| Platform                     | Minimum OS  |
|------------------------------|-------------|
| iPhone, iPad, Mac Catalyst   | iOS 26.0    |
| macOS (native)               | macOS 26.0  |

## Directory layout

```
<TargetName>/
  Sources/    – production code
  Tests/      – unit tests (Swift Testing, not XCTest)
  Resources/  – asset catalogs, etc. (apps only)
```

## Conventions

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- Generated `.xcodeproj` and `Derived/` are git-ignored; never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

## Plans

Implementation plans go in `Plans/` and are named
`<NNN>-<YYYY-MM-DD>-<slug>.md`.
