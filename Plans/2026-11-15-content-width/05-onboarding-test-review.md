# 05 — Onboarding test review

- Status: executing
- Depends on: [04 — Accessibility coverage](04-accessibility-coverage.md)
- Shared context: [Overview](README.md)
- Issue: [STU-331](https://linear.app/kve/issue/STU-331/center-main-screen-content-with-inherited-width-policies)

## Review decision

[Review comment](https://github.com/kyleve/Stuff/pull/506#discussion_r4587492517) asks to delete `OnboardingViewTests`.
The test traverses UIKit scroll-view and page-control internals to check one landscape AX5 arrangement.
Remove the test as requested. Retain the production scrolling fix and all onboarding image configurations and references, including AX5 and phone/iPad accessibility annotations.
The snapshots cover rendering; they do not replace the removed landscape end-of-scroll interaction assertion.
No product API, layout, or architecture change is required.

## Verification and publication

- [x] Regenerate the project, compile the remaining unit bundle, and run the catalog tests and retained onboarding image suite.
- [ ] Review the deletion and unchanged rendering inputs; commit and push the correction.
- [ ] Reply on the review thread and update current PR/screenshot/issue descriptions that refer to the removed test.

The source change is a mechanical test deletion; a separate agent review is not required by the code-review skill.
Keep earlier plans' historical validation counts unchanged.

## Results

- `./test` regenerated the project and rebuilt the remaining unit and image bundles.
- Both Flyover catalog tests and all 11 onboarding captures passed with recording disabled. Capture IDs include phone/iPad AX5 and phone/iPad accessibility annotations. All 11 reference hashes are unchanged.
- `./swiftformat --lint`, `./sf-symbols --lint`, architecture checks, and default host checks passed.
- Completed-diff review against `805dce3af` confirms the sole code change deletes the 77-line test file. Production sources, snapshot definitions, references, and shared test helpers are unchanged. No source or project registration still references the removed suite.

```sh
./test --only WhereUITests/WhereFlyoverCatalogTests \
  --only WhereUISnapshotTests/OnboardingViewSnapshotTests \
  --record never --review --timings
```

## Resume point

Verification is complete. Commit and push the deletion, then publish the review reply and correct current coverage descriptions.
