# Stuff – Repository Shape

## Build system

| Tool  | Version | Pinned via   |
|-------|---------|--------------|
| Tuist | 4.40.0  | `.mise.toml` |

Tuist manifests live at the repo root (`Project.swift`, `Tuist.swift`).
Run `./ide` (or `./ide -i` to also install dependencies) to regenerate the
Xcode project.

## Targets

_No apps or modules yet._ Add targets to `Project.swift` using `macApp()` or `framework()` helpers.

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
