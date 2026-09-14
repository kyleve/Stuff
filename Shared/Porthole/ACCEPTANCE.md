# Porthole acceptance measurements

Use the same hardware, OS, SDK, signing, and compiler configuration for each comparison.
Keep Debug, Beta, and Release results separate. Keep device and simulator results separate.
Record the source revision and whether the source tree contains local changes.

## Disabled composition

The Where controller constructs small registry and presentation objects while disabled.
Its operation journal keeps a URL and loads records only when a caller requests them.
Disabled reconciliation does not install APIs, capture screen values, create provider clients, open a repository workspace, or create a remote host.
The JavaScript session starts only when the console runs with a presentation scope.

These regression tests cover the boundaries:

- `WherePortholeControllerTests.remainsInactiveUntilExplicitActivation`
- `PortholePresentationControllerTests.disabledCompositionDoesNotCreateStorageOrOptionalSubsystems`
- `PortholeHostPresentationModelTests.createsCredentialsAndListenerOnlyAfterExplicitEnable`

Run the shared tests with `./test --porthole-host` and the application tests with `./test WhereUITests`.
These tests establish behavior. Their execution times are not app launch or memory measurements.

## Read observations

Watch uses the shared runtime to sample callable APIs classified as reads.
The form fixes the receiver and arguments for the life of the watch.
Local and remote clients use the same start, read, and stop capabilities.

The observation store holds at most 32 active observations. Each observation retains only its latest result, with a limit of one MiB.
The separate receipt cache holds at most 256 read receipts and eight MiB of encoded results in total.
These bounds do not measure total app memory. Retained arguments, runtime objects, and other app resources consume additional memory.
The [observation store](PortholeRuntime/Sources/PortholeObservationStore.swift) owns the limits for observations, pending reads, and retired identities.

Sample calls and result reads use the bounded memory cache and do not append durable receipts.
Start and Stop use durable operation receipts. A stopped observation identity cannot start again after a delayed request.
Scope invalidation, disabled Porthole, and closure of the owning remote connection stop its observations.
A sequence gap does not supply intermediate values or establish historical execution evidence.

The observation model, invocation model, presentation controller, and runtime tests cover cancellation, delayed callbacks, fixed arguments, and unconfirmed stops.
The [UI tests](PortholeUI/Tests) and [runtime tests](PortholeRuntime/Tests) contain the current scenarios.

## Application verification

UIKit integration tests cover modal presentation, captured issue/day identity, dismissal, and replacement sessions.
Snapshot assertions and visual reviews cover the rendered fixtures.
The user deferred phone installation and the live walkthrough until the phone is available again.
Model tests and synthetic screenshots do not establish that walkthrough.

1. In Beta or Release, enable Porthole through Privacy and Diagnostics. Confirm that the developer menu opens Porthole without provider credentials.
   Confirm that existing DEBUG destinations retain their compilation gates.
   For a fresh demo, enable Porthole before entering demo mode. Privacy and Diagnostics is hidden inside demo mode.
2. Open Resolve as a sheet. Choose a border drift issue. Open Porthole from that detail screen.
   Confirm that the captured issue identity and day match the detail. Close Porthole and confirm that the same detail remains visible.
3. From object evidence, open a callable read and select Watch. Confirm that samples update and retain the original arguments.
   Close the form or Porthole. Confirm that sampling stops before a replacement presentation receives results.
4. Use an isolated fixture to interrupt a remote watch. Confirm that an unconfirmed stop remains visible and permits another stop attempt.
   Confirm that the form blocks another watch until Stop succeeds. Confirm that unknown effects never offer Watch.
5. Use an isolated unreadable investigation fixture. Confirm that Ask shows its setup error while manual tools and reopening remain available.
   Repair the fixture. Retry agent setup. Confirm that retry preserves saved investigation files.

Record and inspect the new invocation, observation, agent setup failure, and Resolve launcher snapshots.
Preserve the production navigation, toolbar, and modal controls in those captures.

The full-menu Porthole-enabled AX5 references retain a known native Toggle track artifact: the track is rectangular around its oval thumb.
The same production row has a correct capsule track in the fixed, first-tile `LogViewModeAX` light and dark references.
The capture cause remains unresolved. These full-menu references do not establish correct native material rendering.
The [SnapshotKitTesting backlog](../SnapshotKitTesting/TODOs.md) records the evidence and capture investigation.

## Bundle size

The read-only report tool consumes completed app bundles. It never builds, installs, launches, or boots a simulator.

```sh
python3 Tools/porthole_acceptance.py \
  --bundle Debug=/path/to/debug/Where.app \
  --bundle Beta=/path/to/beta/Where.app \
  --bundle Release=/path/to/release/Where.app \
  --output .build/porthole-validation/acceptance.json
```

Supply matching `--baseline CONFIGURATION=/path/to/Where.app` arguments to compare builds.
Use a baseline with the same compiler configuration and unrelated source changes removed.
Supply bundles with the same main executable architectures.

The tool reads CPU types and full CPU subtypes from the main executable's Mach-O headers (`CFBundleExecutable`).
A comparison requires the same architecture identities, including subtype capability and ABI bits.
Slice order does not affect the comparison. An arm64 executable and a universal arm64/x86_64 executable do not match.

The tool rejects missing, truncated, unrecognized, or inconsistent executable headers.
It also rejects a configuration stamp mismatch or incompatible platform, SDK, Xcode, optimization, and compilation mode metadata.
A comparison requires known identity metadata and source revisions for both bundles. Missing, blank, or `unknown` identity values cannot establish comparability.
The source revisions can differ. Bundle byte measurements remain available when incomplete metadata prevents a comparison.
It reports missing inputs explicitly. A successful report write never means acceptance passed.

The size metric sums regular-file logical bytes, including embedded frameworks and resources.
The report separately identifies executable bytes, framework bytes, and standalone `.porthole.json` file bytes.
`standalonePortholeCatalogFileBytes` counts only those standalone files. The version-one `portholeCatalogBytes` key remains a compatibility alias for that count.
The exporter embeds API coverage and source archives as compiled Swift constants.
The first measured plugin build also copies standalone coverage catalogs into package resource bundles.
Those duplicate files consume 31,582,785 bytes across the Release app and its two extensions.
The applied plugin correction omits these report outputs while preserving the embedded coverage and source. The final Release measurement contains no standalone catalogs.
Their bytes remain part of executable or framework files and the overall logical size; this report does not isolate them.
The `executableBytes` field measures the main app executable only.
Zero standalone catalog bytes does not mean embedded catalogs use no space.
Each measured bundle includes `catalogSizeDefinition` to explain this distinction.
The report excludes symbolic links. It does not estimate App Store download size or unique APFS storage.

## Launch and memory

`./profile` measures clean builds and test execution. Run it only when no other simulator or build owner is active.
Use Instruments on the target device for app launch and memory observations.
Capture baseline, Porthole disabled, and Porthole enabled runs under the same conditions.
Record cold and warm launches separately. Preserve the trace and the measurement method.

Pass observations through `--runtime-samples /path/to/samples.json`.
The input is a JSON object with `version: 1` and a `samples` array.
Each sample has these fields:

| Field | Required value |
| --- | --- |
| `configuration` | `Debug`, `Beta`, or `Release` |
| `variant` | `baseline`, `portholeDisabled`, or `portholeEnabled` |
| `metric` | `launchMilliseconds` or `residentBytes` |
| `value` | A finite, positive observation; bytes must be whole numbers |
| `platform` | Actual platform, such as iOS device, iOS simulator, or macOS |
| `hardware`, `osVersion` | Exact measurement environment |
| `buildIdentity` | The measured build's source revision |
| `method` | Instrument, capture boundary, and relevant settings |
| `recordedAt` | ISO 8601 timestamp with a time zone |
| `evidencePath` | Existing trace or exported evidence; relative to the samples file or absolute |
| `coldStart` | Boolean, required for launch observations |

The tool preserves every observation and reports count, median, minimum, and maximum.
Different platforms, hardware, build identities, variants, and methods remain separate groups.
It does not infer a performance threshold or treat missing observations as zero.

## Qualification status on 2026-09-14

This checkpoint separates automated checks from installed-app and external acceptance.
The current generator, native, and iOS runs include enum inspection. The iOS run also includes the snapshot-report correction.

| Check | Recorded result | Limit of the evidence |
| --- | --- | --- |
| Generator | 48 tests / 8 suites passed | Real Swift 5/6 fixtures cover optimization, DEBUG conditions, private calls, enum inspection, and rejected actor access. |
| Native runtime and clients | 274 tests / 71 suites passed, including nil/default request options across initial, tool-continuation, and restored agent requests | Scripted providers, GitHub responses, and loopback transport do not establish live-service or physical-pairing acceptance. |
| Separate certificate package | 2 tests / 1 suite passed | Creation and parsing tests do not establish physical transport. |
| Full iOS units | 2,472 tests / 439 suites passed across 27 bundle runs; wrapper duration 149.736 seconds | Includes three snapshot-report regressions. Two known WhereFormat expectations remain. The wrapper's 2,280 entries use a different count. |
| Selected image snapshots | 18 suites passed with recording disabled in 401.809 seconds; zero missing references | Both focused native-toggle references passed. Two full-menu AX5 captures differed by at most two byte values and passed perceptual comparison. The documented native-track artifact remains. |
| Visual review | 76 Porthole references reviewed, including 31 new or changed references; no remaining issue found in that set | Separate reviews cover developer-menu, privacy, and Resolve surfaces. Synthetic fixtures do not establish a live walkthrough. |
| Mac Catalyst client | Release build passed in 55.292 seconds; retained app: 30,547,634 logical bytes. Static inspection and limited live UI smoke passed | Smoke covered launch, credits, and malformed invitation rejection. Real enrollment, pairing, signing, and performance remain unverified. |
| Baseline app products | Debug, Beta, and Release builds passed | Matching configurations remain separate comparison inputs. |
| Application compiler paths | Debug, Beta, and Release iPhoneOS original/instrumented compilation passed for all 19 adopting modules | The original Debug pipeline failed at the checker after compilation. Corrected post-build evidence remains separate. Simulator pairs are pending. |
| Python tooling | 132 tests passed in 18.511 seconds, including the applied packaging and command corrections | Hermetic tooling tests do not compile or launch the app. |
| Static packaging | Release review and separate Beta/Debug app-and-pair checks passed for linkage, resource copies, and app-only App Intents | Seven sampled metadata families have one shared owner. This proves relocatable app closure, not in-place Mac build-directory loading. |
| Final repository maintenance | Attribution is current for Where 17 works and Porthole 10; agent synchronization completed; final two Swift files passed formatting | Other architecture, formatting, SF Symbols, and catalog checks retain their recorded checkpoints. |

The initial Debug pipeline exited 1 after both compilation paths passed. Its checker selected an existing Mac build-directory framework before the app copy.
The applied correction excludes and reports only the exact sibling `PackageFrameworks` runpath for a verified build-product input.
Both actual Debug apps and their paired comparison passed afterward; the initial failed result and report remain unchanged.
Direct outside dependencies, other outside runpaths, escaping symlinks, and metadata ownership still fail. No Swift recompilation was needed.
After the Debug build, the only Swift edits were 12 test-assertion lines and one preference-comment line. The final native run covers those assertions.

The final bundle comparisons measure regular-file logical bytes:

| Configuration | Baseline | Porthole | Difference |
| --- | ---: | ---: | ---: |
| Release | 150,142,312 | 143,075,989 | −7,066,323 |
| Beta | 150,129,553 | 143,075,487 | −7,054,066 |
| Debug | 267,097,699 | 245,088,016 | −22,009,683 |

These differences include the aggregate-library packaging change. They do not isolate runtime cost or measure download size.
The initial Release measurement preceded that correction: 400,309,338 bytes, including duplicate extension code and 31,582,785 standalone catalog bytes.
All three final products contain no standalone catalogs. Embedded source and coverage remain included in framework bytes.
The Debug comparison uses `-Onone` and `singlefile` in both builds, with matching SDK, Xcode, and architecture.
Its final app contains 277 regular files; the baseline contains 236.
Device launch and resident-memory measurements remain pending in every configuration.

The flight/drift regression captures current inputs and replays copied values through production detectors.
It verifies the selected issue and day, source access, and unchanged live scanner state.
It does not reconstruct unrecorded historical inputs or prove the cause of a past execution.

### Evidence locations

The preserved local evidence lives under `.build/porthole-validation`:

| Evidence | File |
| --- | --- |
| Fresh full iOS Swift Testing summaries | `aggregate-ios-tests/Stuff-iOS-Tests.log`, `aggregate-ios-tests-run.log` |
| Final native and certificate qualification | `native-astra-defaults-run.log` |
| Generator qualification | `generator-packaging-run.log` |
| Retained exporter coverage and limits | `final-exporter-review/review.md`, `final-exporter-review/receipt.json` |
| Snapshot assertions with recording disabled | `aggregate-snapshots-run.log`, `aggregate-snapshots/StuffSnapshotTests.log` |
| Limited live Catalyst UI smoke | `catalyst-live-smoke-2026-09-14.json` |
| Corrected Catalyst build and static inspection | `catalyst-release-corrected-memory.json`, `catalyst-final-load-resource-review-2026-09-14.json` |
| Fresh combined iOS build | `aggregate-ios-build-fixed-memory.json` |
| Baseline completion | `baseline-debug-memory.json`, `baseline-beta-memory.json`, `baseline-release-memory.json` |
| Revised visual review | `runtime-revised-snapshot-review.json` |
| Focused native-toggle recording and visual review | `menu-toggle-final-run.log`, `menu-toggle-final-review/receipt.json` |
| Earlier Release/iPhoneOS compiler pair | `compiler-release-iphoneos/result.json`, `compiler-release-iphoneos-memory.json` |
| Final Release/iPhoneOS pair | `compiler-release-final-iphoneos/result.json` |
| Beta/iPhoneOS pair | `compiler-beta-iphoneos/result.json`, `compiler-beta-iphoneos-memory.json` |
| Final Python tooling | `python-final-delivery.log` |
| Packaging guard qualification | `packaging-ci-stage-retained-release-final.json`, `packaging-ci-independent-review.json` |
| Debug compilation and corrected packaging | `compiler-debug-iphoneos/result.json`, `compiler-debug-iphoneos/relocatable-packaging-qualification.json`, `debug-packaging-independent-review.json` |
| Final attribution, formatting, and synchronization | `attribution-final-delivery.log`, `format-final-small-fixes.log`, `sync-agents-final.log` |
| Beta post-build packaging | `compiler-beta-iphoneos/packaging-independent-receipt.json` |
| Final bundle comparisons | `acceptance-release-final-iphoneos.json`, `acceptance-beta-iphoneos.json`, `acceptance-debug-iphoneos.json` |
| Final static linkage and resource review | `compiler-release-final-iphoneos/shared-linkage-review.json`, `release-final-resource-intents/receipt.json` |
| GitHub App registration and installation | `github-app-registration.json` |
| Astra/Sol default-request source review | `astra-sol-sdk-compatibility-review.json` |
| Initial Release bundle comparison | `acceptance-release-iphoneos.json` |
| Prepared physical procedure, not executed | `physical-qualification-manual.md` |

The evidence receipt preserves each Swift Testing summary and sums singular and plural test/suite labels once.
The known issues are the existing `WhereFormatTests.elsewhereCardSubtitleInflectsTheRegionCount` expectations for one and three regions.
The test marks those expectations with `withKnownIssue`.

The earlier combined build completed in 560.953 seconds under the local compiler supervisor.
Its sampled peak aggregate process footprint was 5,064,729,120 bytes, approximately 4.72 GiB.
The Release/iPhoneOS pair completed in 1,247.428 seconds with a sampled peak aggregate footprint of 5,938,520,344 bytes, approximately 5.53 GiB.
The Beta/iPhoneOS pair completed in 1,993.109 seconds with a sampled peak aggregate footprint of 5,903,687,912 bytes, approximately 5.50 GiB.
The Debug run completed in 1,643.656 seconds with a sampled peak aggregate footprint of 5,335,735,712 bytes, approximately 4.97 GiB.
Its exit status was 1 for the initial checker failure; both compilation paths passed and no memory cutoff occurred.
These are build-process observations. They are not application launch or memory measurements.

## Exporter coverage evidence

The retained Release app contains 19 coverage documents with 28 module records and 16,505 catalog entries.
Those records cover the 26 first-party package targets, the local certificate module, and the application target.
The app and shared framework contain 795 source files. Every archived source hash matches its catalog record.
All 26 excluded paths are absent from those source archives. The catalog has no duplicate declaration IDs.

The 19 adopting Swift modules contain 13,542 entries: 5,498 callable plans, 1,609 descriptive entries, and 6,435 unsupported entries.
Other records contain 2,937 source-only debugger declarations and 26 excluded-file entries.
The inventory retains 1,457 conditional entries across all origins, including inactive declarations.
These are shipped source and planner counts. They do not measure active handlers or prove that each call executes on the phone.
Runtime discovery classifies actual installed handlers separately; that classification has compiler-fixture coverage.

The largest rejection groups are unknown receiver isolation, inferred property types, and unbound generic types.
Their counts are 2,796, 721, and 502. Individual coverage entries retain the exact reason, signature, source location, conditions, and hash.
Inventory covers explicit declarations. Function locals, synthesized macro members, and implicit memberwise initializers are outside it.

The preflight detects supported unconditional private-name collisions across files and reports their names and paths.
Conditional collisions and other semantic ambiguity remain compiler checks. The current preflight does not promise exhaustive early detection.
The paired compiler record supplies the actual iOS SDK and target identity; package catalog toolchain text also contains a sysroot warning.

## Implementation boundaries

The catalog inventories first-party application modules and the native debugger modules in the process graph.
Application modules receive generated bindings. Native execution and credential machinery has source-only entries or explicit exclusion records.
The boundary also covers harmless declarations in those native modules. It prevents automatic access to trusted approval and credential APIs.
It does not remove ordinary application declarations from the coverage report.

Generated enum inspection reads the active case and associated values through a compiled typed switch.
It preserves actor ownership and returns direct scalar values or scoped handles for complex payloads.
The compiler fixture verifies that application encoders and computed getters do not run.
Unsafe payloads, unavailable cases, and unbound owners retain explicit unsupported inspection entries.
Other unsupported signatures remain explicit, including unbound generics, executable callbacks, unsafe pointers, noncopyable values, subscripts, and failable initializers.
Value mutation without an actor-owned reference also requires a dedicated adapter.
Inferred property types and unknown receiver isolation can also prevent generated invocation. Each such declaration remains visible with its reason.
The catalog does not promise universal Swift invocation.

Historical recording, cloning arbitrary live objects, forced Swift termination, and applying source changes without another build remain outside this milestone.
The supported experiment path copies values and uses explicitly disposable dependencies.

## Pending acceptance

The user deferred installation and all physical/live-phone tests until the phone is available again.
No Where app was installed or launched on the phone during this task. Continue the independent Mac checks while these tests wait.

- Complete the remaining simulator compiler pairs. All three iPhoneOS configurations passed both compilation paths under matching settings.
- Complete runtime qualification for the shared product in the app, widgets, and share extension. Static Release metadata and resource checks passed.
- Verify extension resource loading, App Intents execution, and inactive debugger services under the new linkage. Static metadata ownership checks passed.
- Complete real enrollment and transport qualification in the Mac Catalyst client. Its limited live UI smoke passed; signing and physical pairing remain unverified.
- Run the installed-app walkthrough above, including all-build activation, retained drift origin, Watch/Stop, and setup recovery.
- Run optimized private bindings on a physical iPhone. Verify cancellation, stale handles, and disabled-resource behavior there.
- When the phone is available, enter the OpenAI key in its secure field and qualify `gpt-6-astra`.
  Exercise streaming, dynamic tools, cancellation, network failures, and conversation restoration.
- Qualify Anthropic for the same scenarios after an API key becomes available. Its live credential check is currently blocked.
- Complete GitHub device sign-in, reviewed draft publication, uncertain retry, and CI display. Registration and the Stuff-only installation are complete.
- Pair a physical iPhone and Mac. Reject incorrect, expired, reused, and revoked enrollment credentials, including active-session revocation.
- Measure cold/warm launch and resident memory for baseline, disabled, and enabled Porthole on the same physical device.
- Complete the distribution review. App Review acceptance is an external requirement and remains unverified.

Porthole Debugger was registered on 2026-09-14 and installed for `kyleve/Stuff` only, with device flow enabled.
Its public client ID is `Iv23liAgmnpuHEZ7dbl9`. No client secret or private key was generated.
Device authorization and live publication have not run. Physical pairing and App Review acceptance remain unverified.
OpenAI live qualification waits for phone availability and secure in-app key entry. Anthropic also lacks an API key.
A read-only SDK review found no incompatibility in the current default requests for Astra or Sol. It does not establish live-provider acceptance.

The Beta checker passed for both completed apps and their paired comparison. Its receipt remains separate from the completed compiler result.
The check preserves complete resource equality between each app and its extensions. Across builds, it excludes only opaque `WhereAssets/Assets.car` payload hashes.
Asset rendition and NLU internals, plus runtime resource and shortcut behavior, remain separate checks.

The raw Release packaging report retains its App Intents metadata difference. The independent review found only accepted input-type ordering changes for year parameters.
That review preserves six action identifiers, four shortcuts, the region entity/query identifiers, and absent extension metadata. It does not execute those routes.

The reboot removed the earlier temporary measurements. Those paths remain invalid as evidence.
Preserve replacement products, reports, and runtime traces outside temporary directories before citing overhead results.
