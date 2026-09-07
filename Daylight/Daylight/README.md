# Daylight

The application composition root and bundled attribution. [Daylight](../README.md) describes setup and operation. The root Package.swift and Project.swift define the targets.

Create the camera, archive, logging system, and destination once. Inject the same instances into every consumer. Keep screen implementations in DaylightUI.

Tests use injected services. The application remains disarmed on a fresh installation. Camera access and Photos access require the system permission prompts.

Mastodon configuration failures remain isolated to publishing. They do not prevent the camera and local capture services from starting.
