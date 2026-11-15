# Flight-review contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Keep the raw GPS path visible in correction reviews after samples lose attribution.
  Bound display geometry without changing the evidence or edits. Never join separate recording devices into one route.
- Route automatic GPS fixes through Core's sample-correction coordinator. Keep
  stale Apply results open for review and preserve manual editing while arrival is pending.
  Show each flight's own progress when a daily review mixes completed and pending flights.
  Retain pending information through Core's `dismissingProposal()` when dismissing completed-flight edits.
- Resolve historical device labels through `DeviceRecordingController.displayNames()`, not the active device list.
- Render point decisions from Core's reviewed corrections. Keep the review open after inclusion or restoration.
  Clear a pending confirmation when its evidence changes. Guard: `FlightReviewModelTests`.
- Keep each actionable flight point row as one accessible button, including its evidence and coordinate label.
  Use the recorded coordinate for its map preview, including excluded points. Keep the preview noninteractive.
- Use this installation's assessment for a live flight notice. Identify each
  recording device in shared reviews and retain historical pending review access.
