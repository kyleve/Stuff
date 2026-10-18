# Flight inference

This directory owns flight inference over raw observations.
The [data-resolution rules](../AGENTS.md), [module rules](../../../AGENTS.md),
and [repository rules](../../../../../AGENTS.md) also apply.

- Assess each recording device separately before calendar bucketing.
  Keep legacy samples in a separate track.
- Preserve unknown observations. Never infer arrival from silence, midnight, or restart.
- Keep later flight observations out of older pending assessments.
- Keep ground confirmation separate from arrival timing. Derive flight days from supported intervals, never an unsupported arrival gap.
  For uncertain arrival timing, exclusion eligibility requires independently supported airborne identities.
  Guards: `FlightAssessmentTests`, `FlightTrajectoryAnalyzerTests`, and `FlightPointCorrectionAssessmentTests`.
- Ground episodes require positive same-device observations. Sparse stationary and moving-ground evidence must satisfy their distinct policy and sensor gates.
  Guard: `FlightGroundInferenceTests`.
- Keep recording gaps out of observed legs and automatic point exclusions.
  Corroborated displacement can establish a trip. Require independent nearby observations at both endpoints.
  Derive travel speed from positional distance and elapsed time, accounting for both endpoints' uncertainty.
  Reported speed alone cannot establish flight. Require support to favor its own endpoint beyond positional uncertainty.
  Search bounded windows across consistent intervening fixes. Stop at confirmed ground episodes.
  Keep recognition accuracy separate from correction eligibility.
  Preserve ground endpoints. Guard: `FlightDisplacementInferenceTests` and `FlightTrajectoryAnalyzerTests`.
- Corroborate resumed cruise points separately and expose each inference reason.
  Require correction-quality positions for positive gap and sensor corroboration; coarse observations may still veto.
  Guard: `FlightEndpointInferenceTests`.
- Put shared inference limits in `GPSCorrectionPolicy`.
  Document evidence decisions beside the algorithm that uses them.

`FlightTrajectoryAnalyzerTests` covers these boundaries with synthetic trajectories.
