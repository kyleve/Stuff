# DaylightCore

Daylight's capture domain, solar scheduling, photographic recipes, image selection, durable staging, and publishing interfaces. Library targets live in the root Package.swift. See [Daylight](../README.md) for operation and limits.

`CaptureSettings.standard` specifies San Francisco and 13 slots per event. `SolarCalculator` computes events offline. `CaptureStore` atomically persists versioned records; unknown versions and damaged records throw. `PublishingDestination` consumes typed image events and persists adapter checkpoints through the supplied callback.
