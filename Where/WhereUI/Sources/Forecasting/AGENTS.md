# Planning presentation contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

- Keep itinerary persistence, forecast bounds, overlaps, and Home projections in WhereCore.
  `LocationForecastModel` mirrors one planning snapshot through store-change refreshes.
  Complete the latest started read when its requesting sheet disappears; keep older results from replacing it.
- Keep each planned stay independently editable by its stable ID. Keep Home separate from tracked regions.
- Gate forecast visualizations with `YearReportModel.showsEstimatedTimeAndPlanning`.
  Hiding estimates must preserve every stay and the Home setting. Settings can still open the planner.
- Keep calendar and timeline projections separate from recorded history. Label possible dates and Home assumptions.
  Guard: `LocationForecastModelTests` and `EstimatedTimeAndPlanningSettingsModelTests`.
- Keep future itinerary years selectable while annual estimates remain current-year-only.
  Guard: `YearReportModelTests.futureItineraryYearsRemainReachableWithoutEnablingAnnualEstimates`.
  The read-only Estimated Time gallery keeps explanatory forecast examples
  visible in grayscale when Off; it must not activate planning.
