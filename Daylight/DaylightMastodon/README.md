# DaylightMastodon

Mastodon account settings, Keychain credentials, and delivery checkpoints. [Daylight](../README.md) describes setup and operation. The root Package.swift and Project.swift define the targets.

Import DaylightCore and system frameworks. Do not import app or UI code. Persist checkpoints before status submission. Never send credentials across origins.

Tests use injected services. The application remains disarmed on a fresh installation. Camera access and Photos access require the system permission prompts.

Status retries check both wall time and uptime before submission. Clock changes, reboot, and checkpoints without an elapsed-time record require reconciliation. Damaged settings disable publishing and expose a configuration issue. Reconnecting preserves the damaged file and starts with automatic publishing disabled.

History supports retry, confirmed absence, and recording an existing post URL. Uncertain submissions cannot use ordinary retry after expiry. Confirmed absence refreshes upload and caption settings while retaining the original account binding. Existing-post URLs must belong to that server. The engine retains replaced checkpoints as delivery recovery history.
