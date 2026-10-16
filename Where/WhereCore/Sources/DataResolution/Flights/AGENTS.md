# Flight inference

This directory owns flight inference over raw observations.
The [data-resolution rules](../AGENTS.md), [module rules](../../../AGENTS.md),
and [repository rules](../../../../../AGENTS.md) also apply.

- Assess each recording device separately before calendar bucketing.
  Keep legacy samples in a separate track.
- Preserve unknown observations. Never infer arrival from silence, midnight, or restart.
- Keep later flight observations out of older pending assessments.
- Keep recording gaps out of observed legs and automatic point exclusions.
  Corroborated displacement can establish a trip. Require independent nearby observations at both endpoints.
  Search bounded windows across consistent intervening fixes. Stop at confirmed ground episodes.
  Keep recognition accuracy separate from correction eligibility.
  Preserve ground endpoints. Guard: `FlightDisplacementInferenceTests` and `FlightTrajectoryAnalyzerTests`.
- Corroborate resumed cruise points separately and expose each inference reason.
  Guard: `FlightEndpointInferenceTests`.
- Put shared inference limits in `GPSCorrectionPolicy`.
  Document evidence decisions beside the algorithm that uses them.

`FlightTrajectoryAnalyzerTests` covers these boundaries with synthetic trajectories.
