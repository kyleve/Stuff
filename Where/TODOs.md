# App todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- feat: Add log viewer to settings page"
- Nest tasks that depend on other tasks.
- Don't delete completed tasks, move them to the "Completed issues" section at the bottom.

# Open issues

## PX (Exploratory)
- File system containerization for more structured storage.
- Thinking outloud, every write into the DB results in various "view" and output changes; but nothing really changes beyond that if writes havent happened. What if we established a pipeline that is:
	1) Write into DB
	2) Kick off async jobs to re-evaluate DB contents
	3) Write out views into a table
	4) Consumers consume those view changes
This feels like it might result in a cleaner "pipeline-esque" code layout, and also importantly, will short-circuit a lot of work?
- I still think _WhereServices_' sub-services should be optional based on the current state of the application. Worth trying to see what happens. Or better yet, decompose it all into an enum representing "logged in" vs "logged out" state.
- For logging out / resetting, why do we need to delete all the DB entries? Could we just write the DB into a folder, and on reset, move to another one?
- Noticed when I don't move for a day, nothing gets recorded. I assume this is because we're relying on GPS updates for updates in the background. Any way to guarantee a daily boot outside of GPS?

## P0s (Must do)
- Remove the `waitForOneRunloop` calls added to UI tests; it's a flake paradise.
- Performance pass (How often is the app booting? Can we only do it on changes of say, 1km or more?)
- Schedule local push notifications if we haven’t recorded for the day yet
- Add snapshot images to a new test target

## P1s (Should do)
- `WhereModel` is also getting quite large. Break it up into one parent with children we can pass down.
- Rewrite controller layer to be a state machine so invariants can’t exist
- SwiftData browser
- What’s with all the `.accessibilityIdentifier(…)` modifiers, do we need them?
- Remove get/set closure-based bindings
- Add a UI that represents where you currently are? Maybe a border on the current location card?

## P2s (Nice to have)
- The `guard let controller else { return }` in the WhereModel in WhereUI is weird
- refactor: Move `RegionDays` / `RegionRanking` down from `WhereUI` into `WhereCore` so `DataIssueScanner` can derive primary regions itself instead of `WhereSession` passing `primaryRegions` in. Reverses the current "ranking is a presentation concept" placement; check the widget/UI call sites still compile.
- Raw data browser (similar to SD browser)
- Move `let calendar = Calendar.current` into a var on the controller? There’s a few of these
- Move test only code behind @_spi
- Add comments to strings in xcstrings files
- Can we code-gen the strings.swift file somehow so we're not referencing the string keys manually?

# Completed issues

## P0s (Must do)


## P1s (Should do)
- refactor: Live-refresh the Primary / Calendar / Resolve UI off a single store-change signal. Every committed write (manual edit, live GPS, CloudKit remote import) emits `WhereStore.changes()`; `WhereSession.observeDataChanges()` re-pulls report + data issues, so the UI can't go stale behind an out-of-band write.
- Export / import system (JSON? Zip?)
- feat: Include data-resolution dismissals (`SDDismissedIssue`) in the backup export/import format, so a replace-import doesn’t silently re-surface issues the user already dismissed. (`BackupArchive.dismissedIssues` round-trips `DismissedIssue` value types, preserving `dismissedAt`.)
- Schedule local push notifications if we haven’t recorded for the day yet
- refactor: `WhereController` is getting quite big. Break it up into one parent controller with children. (dissolved into `WhereServices` + focused collaborators)
- Remove `caption(forRank rank: Int) -> String?`, I don’t want the caption

## P2s (Nice to have)
- refactor: Clean up and centralize loggers into a logging module — added the `LogKit` facade (`WhereLog.channel`) and a DEBUG-only in-app log viewer (`LogViewerUI`, Settings → Developer → Logs)
