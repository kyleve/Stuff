# App todos

## Usage
- Tag issues with conventional commit semantics: feat, fix, refactor, perf, test, docs
	- Eg "- [ ] feat: Add log viewer to settings page"

## P0s (Must do)
- [ ] Performance pass (How often is the app booting? Can we only do it on changes of say, 1km or more?)
- [ ] Schedule local push notifications if we haven’t recorded for the day yet
- [ ] Add snapshot images to a new test target

## P1s (Should do)
- [ ] Rewrite controller layer to be a state machine so invariants can’t exist
- [ ] SwiftData browser
- [ ] Do we live refresh the Primary UI / Elsewhere UI? Or regularly?
- [ ] Export / import system (JSON? Zip?)
- [ ] Schedule local push notifications if we haven’t recorded for the day yet
- [ ] What’s with all the `.accessibilityIdentifier(…)` modifiers, do we need them?
- [ ] Remove `caption(forRank rank: Int) -> String?`, I don’t want the caption
- [ ] Remove get/set closure-based bindings
- [ ] Add a UI that represents where you currently are? Maybe a border on the current location card?

## P2s (Nice to have)
- [ ] The `guard let controller else { return }` in the WhereModel in WhereUI is weird
- [ ] Raw data browser (similar to SD browser)
- [ ] Clean up and centralize loggers into a logging module? We have several separate loggers
- [ ] Move `let calendar = Calendar.current` into a var on the controller? There’s a few of these
- [ ] Move test only code behind @_spi
- [ ] Add comments to strings in xcstrings files
- [ ] Can we code-gen the strings.swift file somehow?
