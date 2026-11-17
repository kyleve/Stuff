# Focus calendar content on representative months

Status: outline
Dependencies: none; execute after plan 01 for separate commits and evidence.
Requirements: [US-01, R-02–R-04, X-01–X-02](README.md#requirements-and-scope).

Replace repeated year-long detail captures with one production month carrying the state's meaningful content. Retain a small full-height integration set and the distinct year-overview layout. Keep production-shaped fixture data and explicit capture identities.

Refine Q-02 after inspecting the existing CalendarModel/MonthGridView boundary, fixture dates, YearView wrapper risks, and full-height dimensions. Record an explicit before/after matrix, selected months, any new shared rendering seam, and visual acceptance before implementation. Then record intentional reframing separately, inspect output at normal and large text sizes, assert unchanged/new references, and run affected model/view/catalog tests. Update documentation invalidated by the new coverage boundary.

The implementation may reuse MonthGridView directly or share its report-to-view wiring with CalendarContentView. Do not add a production snapshot-only month filter. A diagram and Swift sketch depend on the selected seam.

Resume: select and review the coverage matrix while plan 01's checks run.
