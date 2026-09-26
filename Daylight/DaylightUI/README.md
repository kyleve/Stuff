# DaylightUI

SwiftUI presentation, Broadway appearance, and observable models. [Daylight](../README.md) describes setup and operation. The root Package.swift and Project.swift define the targets.

Import Core and Mastodon contracts. Keep capture and persistence in services. Route screen actions through DaylightModel.

Tests use injected services. The application remains disarmed on a fresh installation. Camera access and Photos access require the system permission prompts.

The setup screen starts live framing and requests camera access independently of archive loading. Archive failures remain visible and keep capture controls disabled. Photos access is requested when saving a test shot or arming capture.

Foreground runs carry an ownership identity. A completed capture cycle cannot undo a stop action, and cleanup from an older run cannot stop the current session. Camera stop operations finish before a new preview or foreground run starts.

Sequence history links to Photos and publishing recovery forms. Unknown outcomes require checking Photos or the original Mastodon account before creating replacements. Users can record an existing post URL without publishing again. Recovery forms include standard and accessibility snapshot coverage.
