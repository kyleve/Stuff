# DaylightCore

Daylight's capture domain, solar scheduling, image selection, durable staging, and publishing interfaces. Library targets live in the root Package.swift. See [Daylight](../README.md) for operation and limits.

`CaptureSettings.standard` specifies San Francisco and 13 slots per event. `SolarCalculator` computes events offline. `CaptureStore` atomically persists versioned records; unknown versions and damaged records throw. `PublishingDestination` consumes typed image events and persists adapter checkpoints through the supplied callback.

Capture records from before RAW support can omit format and delivery checkpoints. Reading these records preserves their Photos identifiers. Missing format means unknown; a missing delivery checkpoint means no recorded completion.

Highlight selection remains pending until delivery registration completes. Capture readiness is injected separately from camera access requests so lifecycle tests can exercise permission and thermal failures.
