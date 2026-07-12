// WhereIntents is the App Intents layer of the Where feature: the query and
// action intents that bring Where's region/day-count data and manual logging to
// Siri, Spotlight, and the Shortcuts app, plus the interactive snippet cards
// those intents present.
//
// It is a thin adapter over `WhereCore` (`WhereServices.forIntents()` opens the
// shared App Group store) that renders results with `WhereUI`'s snippet views.
// The `AppShortcutsProvider` that surfaces phrases to Siri lives in the Where
// app target so system metadata extraction always discovers it. See
// `README.md` and `AGENTS.md` for the module shape.
