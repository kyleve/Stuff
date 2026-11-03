# Multi-device recording

This document defines the replacement direction for exclusive recording authority.
It is the design foundation for a new stack based on `main` at `93062f7c`.
This slice changes documentation only. The behavior described here is proposed unless the text identifies an existing implementation.
This document also owns the implementation plan for the replacement stack.

## Why

The previous authority model gives recording a clear owner and makes the origin of location history explicit.
That certainty is useful when a user replaces a phone or wants one dedicated recording device.
However, exclusive ownership makes routine changes between devices require a recording handoff.

The motivating case is everyday use of an iPhone Duo alongside an iPhone Pro Max.
The device that accompanies the user can change several times during a day.
Recording must accommodate that pattern without requiring the user to manage ownership before each outing.

Observations from several devices preserve evidence that later decisions can use.
Automatic selection, suggested resolutions, and manual choices can filter that evidence into useful history.
Those decisions can change as more observations arrive or the user corrects an inference.
An observation that no device recorded is unavailable for any later correction.

The coarse regions in Where make this approach practical.
Phones several kilometers apart within the same region can agree completely about the region history.
When devices disagree across regions, movement can help identify the device that accompanied the user.
A moving phone and another repeatedly reporting from home provide a useful automatic-selection case.
Ambiguous evidence still needs review, and every automatic selection remains reversible.

This approach moves complexity from recording permission and handoffs into evidence assessment and history resolution.
It does not promise less total implementation work.
It supports flexible device use while preserving clear provenance and a coherent account of the history.
The new stack starts from main so each reused component serves this model without unnecessary ownership machinery.

## Product contract

Each device can record with its own local consent.
Where retains the observations and their device provenance.
History selection determines which observations represent the user for a period.
Selection never requires another device to stop recording.

A user can carry different phones during one day.
Selection applies to bounded periods. A whole-day choice is a convenience over those periods.
The day remains a useful review unit, with the existing calendar and time-zone rules for reports.

The first version automatically selects a device when the evidence is strong.
Each automatic decision exposes its reason and supports a manual override.
Ambiguous conflicts remain available for review.
The first version includes setup, temporary device controls, and guided review of unresolved issues.

## Device identity and setup

A new physical phone always receives a new recording identity, including after backup restore or direct device transfer.
Historical observations keep their original device identity.
Neither account sync nor backup import adopts another installation's live identity or local recording consent.

Recording identity uses a nonsynchronizing Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` accessibility.
Apple documents that this accessibility permits access after the first unlock and prevents migration to a different device.
See [Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).
An inaccessible Keychain item produces a retry or unlock state, never a replacement identity.
Device restore and direct transfer require physical-device validation before release.

Setup asks whether this phone is an additional device or replaces an existing device.
An additional device keeps the existing devices active.
A replacement still receives a new identity and offers removal of the selected old device through the existing removal contract.
Earlier history retains its original provenance.
Setup also establishes local recording consent. The replacement choice never transfers consent from another phone.

A replacement device can use the explicit shared-data upgrade action described under [Compatibility](#compatibility).
It does not inherit the old device's recent-contributor status.

## Temporarily ignore a device

The device detail screen includes an **Ignore this device until** row with a `CalendarDay` picker.
The control applies across the account. Raw observations remain stored, and local recording consent remains unchanged.
It changes history selection rather than remotely pausing the location service.

The ignored interval starts now and includes the selected day.
For example, November 8 means through the end of November 8 in the time zone where the user made the choice.
The stored choice retains the selected day, time zone, and resolved time boundary.
Later travel does not move that boundary. Earlier observations remain unaffected.

Automatic selection excludes the device during this interval, even with strong movement evidence.
The user can change the end date or select **Resume now**.
Resume ends the interval going forward and preserves the elapsed ignored interval.
A separate undo action restores eligibility for the elapsed interval.

Expired intervals remain durable decisions.
The filter uses observation time, so late uploads from an ignored interval remain ignored after its expiry.
An offline device applies the shared decision after sync. The UI does not promise immediate remote control.
The existing permanent **Remove device** action remains available for lost, stolen, or replaced devices.

## Region agreement and movement

Different coordinates in the same effective region do not create a region-history conflict.
Those observations remain distinct records with their original coordinates.
Region agreement does not justify joining different devices into one physical trajectory.

A region conflict requires competing evidence for the same period.
Different regions at different times can describe ordinary travel.
Comparing each device's whole-day region set is insufficient.
The resolver accounts for observation times, gaps, accuracy, and existing region corrections.
Different timestamps alone do not establish a coherent journey.

Movement provides evidence about which device accompanied the user.
A coherent moving track can outweigh fresh, repeated stationary observations from another device.
A single distant point, GPS noise, or better accuracy alone does not establish that choice.
The number of devices does not establish the location of the user either.
Two phones at home do not automatically outvote one phone that accompanies the user.

Missing observations provide no stationary evidence.
A device without observations adds no competing track for that period.
Its last position does not extend across an unbounded gap.
The absence of another track also does not increase the quality of the available observations.

Movement remains an inference about the user.
For example, a moving phone can travel with someone else while the user stays home.
The user can correct that inference without losing either track.
Stationary observations can also provide useful history. Movement is not a requirement for a device to contribute.

### Regular homes and temporary bases

The user can optionally specify a precise regular home location in each primary region.
They can also specify dated temporary bases, such as a different New York hotel for each trip.
They choose a place on a map or save it during history review.

These places provide supporting evidence for stationary observations and GPS noise.
They can help distinguish a phone left at home from a phone that travels with the user.
They never create recorded presence without observations or override coherent competing evidence or explicit user choices.

Each place has historical validity boundaries.
A new home or hotel does not reinterpret an earlier trip using the latest address.
Late observations use the place context applicable to their observation time.
These precise places remain separate from the existing region-level forecast home and planned stays.

## Review and explicit source choices

The review screen compares device tracks over the same period, including gaps and the resulting region history.
It explains any suggested source and previews the region-days that a choice changes.
One continuous disagreement during a car, train, or plane journey forms one review issue rather than many point-level issues.

**Use this device for this period** creates an explicit source choice.
The user can edit the start and end or choose the whole day.
The choice is exclusive within that period, including gaps in the selected track.
Other devices do not fill those gaps automatically.
Existing GPS and flight corrections still apply within the selected device's track.

**Return to automatic** reverses the explicit choice for the selected period.
The resolver can then reconsider eligible observations from other devices.
Choices for other periods remain intact.

### Evening reminders and guided review

One combined evening local notification covers missing history and unresolved issues, including device conflicts.
It retains the existing category enablement choices and the user-selected reminder time.
The separate daily region-summary notification keeps its own purpose and schedule.

The combined notification describes the remaining work and its counts.
Older unresolved issues remain eligible even when today's history is complete.
Confident automatic selections do not generate issue notifications. Their explanations remain available in the app.
Changes to history or issue state refresh or cancel pending reminders.

A notification opens a guided flow for the issues that it raised:

1. Refresh the referenced issues and omit those that no longer need action.
2. Show one issue with its date, explanation, available actions, and progress through the queue.
3. Offer **Save and continue** and **Skip for now**. A skipped issue remains unresolved.
4. Before a save, verify that the evidence and relevant decisions still match the review.
5. If they changed, show the updated issue before the user commits a choice.

The user can close the flow at any time. Completed choices remain saved.
The issues bar button provides access to the remaining issues and a **Review remaining** action.
Both entry points use the same resolution screens and actions.
New issues stay in the main list rather than extending the notification queue indefinitely.
If no referenced issues remain, the flow shows that they are already resolved.

## Late observations and historical changes

A late upload adds raw evidence. It does not directly add every reported region to the recorded day.
Selection occurs before `DayAggregator` combines effective region presence.
For example, a phone left in New York cannot add New York to a California trip merely because it uploads later.

Explicit period choices remain in force as other devices upload observations.
Ignored intervals also apply by observation time, including after expiry.
Automatic periods use the combined available evidence and the same selection policy regardless of upload order.

Good late evidence can fill missing periods or automatically correct earlier automatic history when the evidence is strong.
The resulting explanation remains inspectable.
Genuinely ambiguous evidence produces a review issue instead of confident presence in every competing region.
A previously populated day is not automatically final. Explicit user choices provide stability for reviewed periods.
Every affected output refreshes after reassessment.

## Data and decision boundaries

Raw observations remain the durable evidence.
Backups and diagnostic review retain their original coordinates, timestamps, accuracy, source, and installation identity.
Automatic selection does not erase observations or rewrite their device identity.
Existing explicit removal, reset, and deletion operations retain their separate contracts.

Automatic decisions are derived results.
Their evidence and policy version explain the result and permit reassessment after late sync or a policy change.
User choices are durable decisions with explicit period boundaries.
They take precedence over automatic selection and remain reversible.

Device selection applies to automatic GPS evidence.
It does not override manual entries, authoritative day overlays, or evidence-derived assertions.
It composes with existing per-sample region corrections.
Legacy samples without a device identity remain available without an invented identity.

Every consumer uses the same effective history contract.
Reports, widgets, reminders, issue scans, exports, and relevant App Intents agree after local writes, remote imports, and user choices.
Raw track review and lossless backups remain available separately.
Flight and movement inference preserve device boundaries.
An unresolved region conflict remains visible to consumers instead of silently becoming a confident combined history.
The exact treatment of unresolved totals remains an activation prerequisite.

## Sync and concurrent decisions

Sync completion describes a local import or export operation. It does not prove that every device uploaded all its changes.
An offline phone can still hold unseen observations or decisions.
[Apple's sync events](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/event/enddate) describe the individual operation boundary.

Each user decision records an immutable operation identity, its authoring device, and the relevant earlier decisions that it saw.
That causal context distinguishes an intentional replacement from independent edits on offline devices.
For example, a decision can record knowledge through Pro Max revision 120 and Duo revision 45.
A per-device counter alone cannot describe that knowledge.

| Relationship between decisions | Merge behavior |
| --- | --- |
| A new choice deliberately replaces an earlier observed choice | Apply the replacement within its specified period. |
| Offline devices make incompatible choices for overlapping periods | Retain both choices and raise an issue for the overlap. |
| Choices concern separate periods | Apply both. |
| Concurrent choices agree for an overlapping period | Treat that overlap as agreement while retaining the decision records. |

Period selections, return-to-automatic actions, and edits to ignore intervals use these causal rules.
Other shared controls define their merge semantics before persistence ships.
CRDTs provide useful models for this behavior, including a multi-value register that retains concurrent choices until a subsequent choice replaces them.
See [INRIA's multi-value register](https://concordant.gitlabpages.inria.fr/software/c-crdtlib/c-crdtlib/crdtlib.crdt/-m-v-register/index.html).
The exact representation can use revision vectors or explicit predecessor identities. This plan does not select a general CRDT framework.

Counters describe decisions actually received and incorporated.
Receipt of revision 50 before revision 49 cannot imply knowledge of every revision through 50.
Counter allocation, persistence, and recovery must prevent reuse after crashes, backup restore, or reset.
Dates remain useful for display and diagnosis. Wall-clock ordering does not decide between incompatible concurrent user choices.

Raw observations merge by stable identity and retain provenance.
Automatic selection recomputes from the available evidence and policy version instead of accepting a remotely chosen derived winner.
Merge behavior must converge after all relevant records arrive, regardless of duplicates or delivery order.
Sync status reports observable facts, such as the last successful operation and known pending changes.
It never promises that every device is fully current.

## Compatibility

The account carries a monotonic minimum data-semantics version, separate from the app version.
It covers incompatible interpretation of stored data as well as structural changes.
An older client cannot ignore source choices and continue to publish different history.

The incompatible-data state uses direct copy:

> **Update Where to continue**
>
> Your data uses a newer format that this version of Where does not support.

A failed compatibility check has a separate retry state. A network error does not claim that the app needs an update.
The gate covers foreground access, background work, relevant App Intents, and published widget output.
It prevents incompatible writes and withdraws misleading output from retired scopes.
An old backup, stale response, or older client cannot lower the required version.

The required version advances when incompatible behavior activates. A routine app update alone does not advance it.
Automatic upgrade eligibility requires a meaningful contribution to effective history within the preceding **15 days**.
Explicit source selection for a period within that window also qualifies the device.
The window uses the observation or selected period dates, not the upload date or the time of the selection action.

Local recording enablement, raw ping volume, and excluded observations do not establish eligibility.
Redundant observations that never contributed useful history do not qualify an idle device.
Useful stationary observations do qualify. Movement is not required.
Old observations uploaded today do not make their device a recent contributor.

Any capable device can offer an explicit **Upgrade shared data** action.
The explanation states that older apps will need an update.
This action supports replacement phones, long absences, and incomplete recent history without a 15-day waiting period.
An ineligible device continues with the current format when it supports that format.
A new empty account initializes with the current supported version.

The recent-contributor rule prevents incidental automatic upgrades from unused devices.
A legitimate upgrade can still require updates on other active devices because the compatibility boundary applies to the account.
No device needs exclusive recording ownership to perform an upgrade.

Compatibility requires a separate offline policy before incompatible behavior activates.
Causal metadata cannot notify an offline older app about an upgrade on another device.
The implementation must define offline capture, reads, writes, verification expiry, and the synchronization point for activation.
The rollout must establish compatibility-aware clients before activating data that older clients cannot safely interpret.
A sync-completion event alone cannot provide that guarantee.

## Required scenarios

| Evidence or action | Expected behavior |
| --- | --- |
| Both phones report different coordinates within the same region | No device conflict. Preserve both sets of observations. |
| One phone travels while another repeatedly reports from home | Select the moving phone where evidence is strong. Explain the selection. |
| Several phones remain at home while one accompanies the user | Assess evidence without a device-count vote. |
| The user changes phones during the day | Permit different selected devices in different periods. |
| One device reports and another remains silent | Assess the available track without inventing a stationary competitor. |
| Two devices travel in different regions during the same period | Request review unless independent evidence supports automatic selection. |
| A sparse track or inaccurate boundary point suggests movement | Preserve uncertainty. Do not classify it as strong movement evidence. |
| Devices disagree throughout a car, train, or plane journey | Review one continuous issue and preview an exclusive period choice. |
| The explicitly selected device has a gap | Preserve the gap instead of filling it from another device. |
| The user resumes an ignored device before the chosen end day | End the ignore interval going forward. Preserve its elapsed portion. |
| An ignored device uploads after the ignore interval expires | Apply the interval to observation times. Preserve the raw uploads. |
| Late observations affect automatic history | Reassess the evidence. Permit strong corrections and expose genuine ambiguity. |
| Late observations conflict with an explicit source choice | Preserve the explicit choice. |
| The user changes a source choice or returns to automatic | Rebuild effective history for the affected period while retaining raw observations. |
| The user selects a new home or a different hotel | Apply the place to its validity period without silently rewriting earlier context. |
| The user exits the notification flow after resolving one issue | Retain the saved choice and expose the remaining issues through the bar button. |
| Another device resolves an issue before the notification opens | Refresh the queue and omit that issue. |
| An idle updated device only produces unused pings | Do not automatically upgrade shared data from that activity. |
| A stationary device contributes useful recent history | Permit it to qualify for automatic upgrade without movement. |
| A replacement phone has no recent contribution | Offer an explicit shared-data upgrade and retain its new recording identity. |
| Two offline devices choose different sources for the same period | Preserve both decisions and request review of the overlap. |
| A decision arrives before one of its predecessors | Preserve incomplete knowledge instead of claiming a complete revision prefix. |

These scenarios define acceptance criteria. They are not claims of current test coverage.

## Formal verification

Protocol activation requires PlusCal specifications checked with TLC.
The models follow the existing [specification workflow](Specifications/README.md) and live under `Where/Specifications/`.
They check narrow properties within explicit bounds and assumptions.
They do not establish an unbounded mathematical proof or prove that the Swift implementation matches the model.
This design slice adds the requirements only. It contains no new models or model-checking results.

| Model family | Required properties | Owning implementation slices |
| --- | --- | --- |
| Decision merging | Replicas with the same complete decision set and protocol version converge regardless of delivery order or duplicates. Incompatible concurrent choices survive until explicitly resolved. Missing revisions never count as observed. Recovery never assigns an existing operation identity to a new operation. Replacements affect only their specified periods. | 1 establishes the model. 4 refines it against durable decisions and counter recovery. |
| History selection | Equal evidence, decisions, policy versions, and query context produce equal history. Late uploads respect explicit choices and historical ignore intervals. Resume, expiry, and undo have distinct effects. Selection preserves raw observations and never fills an explicitly selected device's gaps from another device. | 4 models ignore intervals. 5 completes the model against shared history selection. |
| Compatibility and scope retirement | The required version never decreases. Stale verification cannot restore revoked access. Suspended work cannot commit through a revoked permit. Recovery uses a new scope and permit. Offline behavior follows the selected activation policy. | 3 defines and checks the compatibility protocol. |

Each family uses small models with explicit atomicity, delivery, persistence, and failure assumptions.
The model separates receipt of a decision from knowledge of its dependencies.
Liveness properties state their fairness assumptions separately from safety properties.
No model assumes that every offline device receives a change before it performs another action.

Each model requires:

- Passing configurations that exhaust the stated finite bounds.
- Deliberately broken variants that fail the expected named invariant or temporal property.
- Reachability controls that establish coverage of the critical race or delivery order.
- A README that records bounds, assumptions, exclusions, and correspondence with the implementation and its regression tests.
- Swift regression tests for important counterexamples and the implementation boundaries that the model abstracts.

The owning PR runs the relevant concerns through `./tla-check` and records the checked revision and results.
Before activation, the source correspondence must match the implementation, including suspension points and commit boundaries.
A relevant implementation or protocol change requires another correspondence review and model-checking run.

The existing [remote-device removal model](Specifications/RemoteDeviceRemoval/README.md) supplies useful patterns for reordered delivery, cutoffs, and source correspondence.
The previous stack's `CompatibilityVerification` and `CompatibilityWrites` models provide candidates for selective reuse.
Adaptation must remove recording-owner dependencies and reflect the new offline policy.
Their previous results do not validate the replacement protocol.

The models use representative evidence and time values.
GPS quality, movement thresholds, calendar arithmetic, and actual device transfer still require scenario, property, and physical-device tests.
Model checking cannot establish which phone actually accompanied the user.

## What main already provides

The new stack starts from the existing implementation.
It does not require a wholesale import of the previous stack.

| Existing owner | Reuse boundary |
| --- | --- |
| [RecordingDeviceID](WhereCore/Sources/Devices/RecordingDeviceID.swift) and [LocationSample](WhereCore/Sources/Location/LocationSample.swift) | Installation identity and automatic-sample provenance already exist. |
| [DeviceRecordingController](WhereCore/Sources/Devices/DeviceRecordingController.swift) | Local consent and device lifecycle already operate without exclusive ownership. |
| [LocationIngestor](WhereCore/Sources/Location/LocationIngestor.swift) and [LocationOutbox](WhereCore/Sources/Location/LocationOutbox.swift) | Capture stamps provenance and retains accepted writes across persistence failures. |
| [LocationHistoryReader](WhereCore/Sources/Devices/LocationHistoryReader.swift) | The shared read boundary already applies device removals and region corrections. |
| [LocationHistoryReaderTests](WhereCore/Tests/LocationHistoryReaderTests.swift) | Existing guards preserve raw observations while applying corrections and removal cutoffs. |
| [HomeRegionRecord](WhereCore/Sources/Forecasting/HomeRegionRecord.swift) | The forecast home identifies a region. It does not supply a precise home or temporary base. |
| [ReminderReconciler](WhereCore/Sources/Reminders/ReminderReconciler.swift) and [DataIssueAlertReconciler](WhereCore/Sources/Reminders/DataIssueAlertReconciler.swift) | Missing-history and issue reminders currently use separate notifications. |
| [StoreRemoteChangeSource](WhereCore/Sources/Persistence/StoreRemoteChangeSource.swift) | Imported history refreshes readers. It does not establish knowledge of all devices. |

The current [recording context](WhereUI/Sources/Launch/InstallationRecordingContextStore.swift) uses a file excluded from backups.
It does not yet use the proposed Keychain identity.
The current reader has no device-selection policy or unresolved-conflict result.
It provides an integration boundary, not a completed multi-device resolver.
The existing correction guards do not prove the new acceptance scenarios.

## Previous stack reuse

The previous stack remains a reference at `14d71446e7afe8551da5b20ee8be0bd0dcc668e3` ([PR #457](https://github.com/kyleve/Stuff/pull/457)).
Each imported change requires a concrete need and focused validation in the new stack.

| Previous concern | Treatment in the replacement |
| --- | --- |
| Ownership grants, claims, approval fences, handoffs, and lost-owner recovery | Excluded from the new recording model. |
| Sample ownership IDs and exclusions tied to ownership periods | Excluded. Existing device provenance is the starting point. |
| Device identity and local consent | Start from main and strengthen identity against transfer to another device. |
| Compatibility checks, transaction guards, scope retirement, and stale-output withdrawal | Reuse relevant parts independently of recording ownership. |
| Owner-only compatibility upgrades | Replace with recent-contributor eligibility and an explicit upgrade action. |
| Snapshot references for authority and handoff screens | Excluded. New presentation receives its own fixtures. |

The compatibility policy and rollout gate precede activation of incompatible stored behavior.
Useful old-stack code must satisfy the new contracts and tests before reuse.

## Implementation plan

The stack starts with this design slice. The following slices establish and activate the replacement model.
Each slice receives its own tests and PR.

### 1. Evidence assessment and causal decisions

Define bounded periods, accuracy-aware movement evidence, stationary evidence, and uncertainty around sparse observations.
Model regular homes and temporary bases as optional evidence with historical validity.
Use the required scenarios as executable fixtures.
Preserve same-region agreement and separate device trajectories.
Define causal replacement, concurrent overlap, reversal, and agreement without production writes.
Add the initial decision-merging specification and its TLC control cases.
Exercise reordered, duplicated, and incomplete inputs. This slice does not change production filtering.

### 2. Device identity and setup

Implement device-local Keychain identity with explicit unavailable and recovery states.
Add the additional-device and replacement-device setup choices.
Preserve local consent and the existing removal contract.
Cover backup restore, direct transfer, reset, rejoin, and Keychain failures.
Validate restore and transfer on physical devices before activation.

### 3. Compatibility gate

Selectively reuse compatibility guards, scope retirement, and stale-output withdrawal from the previous stack.
Remove ownership dependencies from these components.
Implement the monotonic data-semantics requirement, recent-contributor eligibility, and explicit upgrade action.
Define the offline policy and activation protocol before incompatible data writes.
Adapt the compatibility and scope-retirement models to that protocol and its actual atomicity boundaries.
Cover stale responses, old backups, failed verification, and foreground and background consumers.

### 4. Durable choices, device controls, and places

Extend the value-based store and backup contracts with source choices, ignore intervals, regular homes, and dated temporary bases.
Implement causal context, durable reversal, and concurrent-choice behavior.
Refine the decision-merging model against persistence, dependency delivery, and counter recovery.
Add history-selection model cases for ignore intervals, resume, expiry, and undo.
Define precedence with per-sample corrections, manual overlays, and device removals.
Cover expiry, time-zone changes, late imports, partial delivery, counter recovery, and both backup import strategies.
Preserve observation provenance and the local identity across account data operations.

### 5. Shared history selection

Extend `LocationHistoryReader` with effective selections and explicit unresolved conflicts.
Apply selection before region aggregation and preserve device boundaries through movement and flight inference.
Cover reports, issue scans, widgets, reminders, exports, and relevant App Intents.
Exercise local writes, delayed sync, user overrides, reset, and device removal.
Preserve raw review, lossless backups, and manual assertions.
Complete the history-selection model and add Swift regressions for its important counterexamples.
Define unresolved-conflict presentation before changing totals.

### 6. Review experience, reminders, and activation

Add the temporary-ignore row, place controls, and inspection of automatic-selection reasons.
Support exclusive period choices, whole-day convenience, return to automatic, and previews of affected region-days.
Combine evening reminders and add notification routing into the bounded resolution flow.
Keep remaining work accessible through the issues bar button.
Use representative phone journeys and concurrent-edit scenarios in previews, snapshots, and interaction tests.
Require passing TLC cases and reviewed source correspondence before activation, as specified under [Formal verification](#formal-verification).
Activate selection after compatibility, durable decisions, shared consumers, and review surfaces satisfy the acceptance criteria.

## Open implementation decisions

The following details require explicit decisions in the relevant slices:

- Interval segmentation, exact boundary inclusivity, and context outside a queried day.
- Accuracy-aware movement and stationary thresholds, place radii, evidence freshness, and sparse-track behavior.
- Precedence between ignore intervals, explicit source choices, per-sample corrections, and manual overlays.
- The representation of causal context, incomplete dependencies, and counter allocation and recovery.
- Meaningful-contribution criteria within the agreed 15-day eligibility window.
- Treatment of unresolved conflicts in totals, history exports, widgets, and reminders.
- Backup, reset, reinstall, rejoin, and device-removal behavior for new identities and stored decisions.
- Offline compatibility policy, activation synchronization, and the required rollout sequence.

Thresholds require named units and scenario tests before they affect history.
The automatic policy produces the same result for the same evidence and policy version, regardless of input or sync order.
The first executable slice establishes that policy without changing capture or report behavior.
Activation follows durable choices, consistent consumer integration, compatibility protection, and a usable review path.

## Pending review discussion

This temporary section preserves unresolved points from the review of `2658e4d4`.
The proposals in this section are not agreed decisions.
Discussion proceeds through R1–R5 first, then E1–E5. D1 and D2 retain the two broader open decisions.
After agreement, update the relevant contract, acceptance scenarios, and implementation steps.
Then remove the resolved entry from this section.
When no entries remain, remove this section.

### R1. P1 — Define compatibility across automatic-selection policy versions

Two app builds can understand the same stored format but use different resolver policies and derive different history from identical inputs.
Recording a policy version explains this difference without preventing it.
The plan needs a rule for compatible policy differences and changes that require the compatibility gate.

The initial proposal selects one account-wide policy through the shared data-semantics version.
This requires newer clients to retain earlier algorithms for as long as accounts use them.
Retaining those implementations indefinitely is not a practical guarantee.

The alternative under discussion uses `major.minor.patch` data-semantics versions and gates access only on an unsupported required major:

- Major: incompatible stored-data or saved-decision semantics that older clients cannot honor.
- Minor: compatible improvements to automatic selection, including new heuristics.
- Patch: bug fixes within the existing shared contract.

Under this alternative, each build uses its current resolver without retaining every earlier implementation.
Same-major clients preserve the shared meaning of raw observations, explicit choices, ignore intervals, and causal decisions.
New controls that older clients cannot honor require a major change.
Compatible resolver versions can produce different automatic history, totals, and issues, even from identical inputs.
The full resolver version identifies derived results and invalidates cached results after an update.
Regression tests check the shared contract across supported versions.
History equality requires identical evidence, decisions, query context, and full policy versions.

The remaining decision is whether automatic-result differences between compatible versions are acceptable until the versions align.
Explicit choices remain durable, and automatic reassessment preserves raw observations.

### R2. P2 — Distinguish an unverified account from a new account

A new installation has an empty local store before existing account data arrives.
Using local emptiness to initialize the latest shared version can bypass recent-contributor eligibility and explicit upgrade consent.
Proposal: distinguish unknown account state, a verified existing account, and a verified new account.
Define what evidence establishes account newness before automatic initialization.

### R3. P2 — Clarify identity across reset, rejoin, and restore

Slice 4 preserves local identity across account-data operations, but the existing reset contract rotates that identity.
The existing rejoin contract also creates a new identity.
See [installation-context reset and rejoin](WhereUI/Sources/Launch/InstallationRecordingContextStore.swift) and their [regression tests](WhereUI/Tests/InstallationRecordingContextStoreTests.swift).
Proposal: specify an operation-by-operation lifecycle for backup import, reset, rejoin, reinstall, and device transfer.
Keychain persistence must support intentional recording-identity rotation and safe recovery of operation counters.

### R4. P2 — Validate the reviewed state atomically with the decision write

A remote decision can arrive between a separate validation and the subsequent save.
If the save adopts the latest causal context, it can supersede a decision that the user never reviewed.
Proposal: bind the operation to the reviewed evidence, decision revisions, and data generation.
Revalidate those inputs inside the guarded write transaction.
The [sample-correction coordinator](WhereCore/Sources/DataResolution/SampleCorrectionCoordinator.swift) supplies an existing pattern.

### R5. P2 — Include historical years in issue reminders

The plan keeps older issues eligible, but the current reminder scans only the current year.
A December conflict can disappear from reminders in January if the new flow retains that scope.
See the [current issue-alert reconciler](WhereCore/Sources/Reminders/DataIssueAlertReconciler.swift).
Proposal: preserve historical year context in issue discovery, notification queues, and review lookup.
Add a year-boundary acceptance scenario.

### E1. Ignore intervals versus explicit source choices

Example: the user selects the Duo for today, then ignores that device until tomorrow.
Define which instruction wins and how the UI explains the result.
The decision must cover existing choices and new choices that overlap an ignored interval.

### E2. Whole-day choices across travel and daylight-saving changes

Define which time zone converts a whole-day choice into a bounded period.
Cover travel after the choice and days that contain fewer or more than 24 hours.
Proposal: retain the chosen `CalendarDay` and time zone alongside fixed instant boundaries.
Clarify how the choice appears when the report uses a different time zone.

### E3. Evening notifications on multiple phones

Notification preferences are local and default to enabled, so both phones can send the combined evening reminder.
See [WherePreferences](WhereCore/Sources/Preferences/WherePreferences.swift).
Define whether the product promises one reminder per device or one reminder across the account.
Specify the device-level controls and defaults independently of recording consent.

### E4. Late observations from the explicitly selected device

An explicit source choice identifies a device and period. It does not currently freeze the reviewed set of observations.
Later observations from that same device can still change effective history inside the chosen period.
Define that behavior and its review or notification consequences without promising that source selection freezes all historical results.
Add an acceptance scenario for late observations from the selected device.

### E5. Queued issues that split or merge after sync

A queued conflict can change its boundaries, split into several conflicts, or merge with another conflict.
An obsolete issue ID must not produce an "already resolved" result while the underlying disagreement remains.
Define how queue entries retain their identity or original review scope through reassessment.
Preserve the bounded notification flow while unrelated new issues remain in the main list.

### D1. Treatment of unresolved conflicts in totals

The document requires visible uncertainty but leaves its effect on counts and exports open.
Decide which region presence contributes to totals while a conflict remains unresolved.
Apply the same rule to reports, widgets, reminders, history exports, and relevant App Intents.
Define the user-visible explanation and acceptance scenarios before the shared-reader slice activates.

### D2. Offline compatibility and activation

An offline older app cannot immediately learn that another device raised the required version.
Define offline capture, reads, writes, verification expiry, and recovery after verification fails.
Specify the activation and rollout protocol, including independent arrival of compatibility metadata and incompatible records.
The compatibility models must check that protocol under explicit delivery assumptions before activation.
