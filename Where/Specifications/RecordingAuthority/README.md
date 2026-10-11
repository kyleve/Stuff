# Recording authority

Run `./tla-check RecordingAuthority`. See the [specification guide](../README.md).

The bounded model has two installations, three server revisions, and two data
versions. A labelled step is one server conditional transaction or a local
capture transition. `observed` represents the revision bound to a proposal.
The model checks normal-handoff recording exclusivity and owner-only version
advancement. The negative control permits a secondary to advance the floor.

Production correspondence: `RecordingAuthorityProposal` supplies transition
rules; transport compare-and-save rejects stale observations. A controller must
stop before approval. The foundation does not yet wire that hardware step.
`RecordingAuthorityTests` cover request invalidation and tenure replacement;
`RecordingAuthorityTransportTests` cover competing claims, lost-response retry,
and stale-owner upgrades. `RecordingAuthorityCoordinatorTests` cover missed
history and disappearance of established authority.

Limits: this is a safety model, not proof of eventual delivery or availability.
It does not model forced recovery (which deliberately permits offline overlap),
CloudKit authentication/errors, timestamp accuracy, or durable local stop intent.
Those require executable controller/transport tests in the integration slices.
