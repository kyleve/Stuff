# Flight inference

This directory owns flight inference over raw observations.
The [data-resolution rules](../AGENTS.md), [module rules](../../../AGENTS.md),
and [repository rules](../../../../../AGENTS.md) also apply.

- Assess each recording device separately before calendar bucketing.
  Keep legacy samples in a separate track.
- Preserve unknown observations. Never infer arrival from silence, midnight, or restart.
- Keep later flight observations out of older pending assessments.
- Keep long gaps out of observed legs. Use corroboration only for the resumed cruise endpoint.
  Preserve ground endpoints and expose the inference reason. Guard: `FlightEndpointInferenceTests`.
- Put shared inference limits in `GPSCorrectionPolicy`.
  Document evidence decisions beside the algorithm that uses them.

`FlightTrajectoryAnalyzerTests` covers these boundaries with synthetic trajectories.
