# StuffCore

Scaffold SPM library for code shared across Stuff apps.
Today it only exposes a placeholder `StuffCore.version` constant.
The module, test bundle, and docs exist before the first real API lands.

Add shared types under [`Sources/`](Sources/) and wire consumers in [`Package.swift`](../../Package.swift).
Run tests with `./test StuffCoreTests`.
