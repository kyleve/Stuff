# Multi-device recording

This document defines the replacement direction for exclusive recording authority.
It is the design foundation for a new stack based on `main` at `93062f7c`.
The design PR changes documentation only. Dependent PRs implement the slices listed below.
The behavior described here is proposed unless the text identifies an existing implementation.
This document also owns the implementation plan for the replacement stack.

The first implementation adds pure assessment and causal-decision types in WhereCore.
It does not activate multi-device selection, change capture, or change stored and backup formats.
The [initial assessment policy](#initial-assessment-policy) and [decision representation](#sync-and-concurrent-decisions) record its technical choices.
The identity slice implements device-only Keychain storage, consent recovery, and additional/replacement-device setup.
Automated restore and transfer validation remain required before activation.

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
Selection supports whole-day choices and bounded time ranges.
A whole-day choice uses the recording device's logical `CalendarDay`. A time-range choice retains fixed start and end instants.

The first version automatically selects a device when the evidence is strong.
Each automatic decision exposes its reason and supports a manual override.
Ambiguous conflicts remain available for review.
They require user input before disputed presence contributes to totals.
The first version includes setup, temporary device controls, and guided review of unresolved issues.

## Device identity and setup

A new physical phone always receives a new recording identity, including after backup restore or direct device transfer.
Historical observations keep their original device identity.
Neither account sync nor backup import adopts another installation's live identity or local recording consent.

Recording identity uses a nonsynchronizing Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` accessibility.
Apple documents that this accessibility permits access after the first unlock and prevents migration to a different device.
See [Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly).
An inaccessible Keychain item produces a retry or unlock state, never a replacement identity.
Automated lifecycle fixtures gate restore and transfer behavior. They model Keychain accessibility, nonmigration, and backup exclusion explicitly.
Document these platform assumptions beside the fixture; do not report fixture results as physical-device measurements.

Identity and consent follow this lifecycle:

| Operation | Recording identity and consent behavior |
| --- | --- |
| App update or ordinary relaunch | Preserve the local identity and consent. |
| In-app backup import, including replace | Preserve this installation's identity and consent. Never adopt them from the archive. |
| Explicit app reset | Create a new identity and request recording consent again. Apply the existing data-reset contract. |
| Rejoin after removal | Create a new identity and request recording consent again. Keep the old removal effective. |
| Reinstall or system restore on the same phone | Reuse a surviving valid Keychain identity. If it is absent, create a new identity through setup. Request recording consent again. |
| System restore or transfer to another physical phone | Create a new identity and establish local consent through setup. Preserve historical provenance. |

A removed identity remains retired. Rejoin never revives that identity or removes its removal records.
Retained historical observations and decisions keep their original device and operation identities.
Identity reuse must preserve the uniqueness of decision operation identities, including after reinstall or restore.
An older backup cannot restart counter allocation for an existing identity.

Setup asks whether this phone is an additional device or replaces an existing device.
An additional device keeps the existing devices active.
A replacement still receives a new identity and offers removal of the selected old device through the existing removal contract.
Earlier history retains its original provenance.
Setup also establishes local recording consent. The replacement choice never transfers consent from another phone.

Setup shows this phone's reminder settings separately from recording consent.
The user can change these settings later in Settings.

A replacement device can use the explicit shared-data upgrade action described under [Compatibility](#compatibility).
It does not inherit the old device's recent-contributor status.

### Required attribution and pre-release conversion

Every automatic GPS observation admitted to the replacement model requires a recording-device identity.
Missing attribution is invalid data that requires repair. It is not another selection category or permission to exclude an observation silently.
Manual entries and evidence-derived assertions retain their separate source contracts.

Where has not shipped. Existing data follows the established export, offline conversion, and replace-import process before the new contract activates.
Conversion belongs in `Where/Tools/upgrade-backup.rb`, with a corresponding backup-format change.
The runtime requires the current shape without an unattributed-GPS fallback or migration during reads.
Compatibility protection and data repair precede activation of this incompatible contract.

Conversion preserves existing device identities and assigns missing attribution through an explicit mapping to the historical source device.
It never assumes that the importing phone produced the observations or combines unknown sources into one invented device.
Incomplete mappings stop conversion without modifying the input archive.
Conversion preserves sample identities, coordinates, timestamps, accuracy, motion, correction history, and evidence assets.
Reusing a mapping across archives preserves the same historical device identities.

Export existing data before installing code that rejects its old shape.
Validate the converted archive through the production backup decoder before replace-import.
Reject automatic GPS without attribution at admission, including backup import and remote-store reads.
Preserve invalid persisted evidence for repair and expose the failure instead of publishing apparently complete history.

## Observation time and recording day

Each automatic observation retains its absolute timestamp and a recording-day assignment.
A resolved assignment stores a logical `CalendarDay` and the time-zone context used to establish it.
The recording day means the recording device's local Gregorian date at the observation time.
The assignment remains stored through sync, backup import, and later travel.
Reports group selected observations by this recorded day instead of recomputing it in the viewing device's current time zone.
Retaining the timestamp and time-zone context also preserves the information needed for future projections.

Absolute timestamps remain authoritative for ordering, movement, competing-track comparisons, and fixed time-range choices.
The resolver first compares full timestamps and bounded track coverage to establish overlap.
Sharing a UTC calendar date alone does not establish overlap.
Two devices can label the same instant with different recording days.
Their observations still compete when they cover the same absolute period.

Whole-day source choices identify the selected device and logical `CalendarDay`.
Their coverage follows that device's recorded calendar context and can contain separate intervals in absolute time.
Every portion labeled with the chosen day belongs to the choice. Intervening portions labeled with another day remain outside it.
For example, a December 8 choice includes both December 8 portions in a December 8 → December 9 → December 8 journey.
Other devices cannot bypass that choice by assigning another date label to overlapping observations.

A GPS gap remains within a whole-day choice when the recorded calendar context establishes its coverage.
The selected device remains exclusive through that gap.
If missing recorded calendar context leaves coverage ambiguous, require clarification before saving a whole-day choice.
The existing fixed time-range option remains available. It does not resolve missing recording-day assignments or permit guessed dates.

Delayed callbacks use the observation time, never the callback, upload, or import date.
The device's current time zone cannot establish its earlier time zone after an unobserved change.
If the observation-time context is unavailable, retain the raw observation and expose an unresolved day assignment instead of guessing.
Define the capture and recovery protocol before activation, including how an unresolved assignment becomes resolved.

Historical conversion establishes missing day assignments from supported metadata or explicit mappings, while preserving original timestamps and existing assignments.
The conversion must not silently use the importing device's current time zone.
Manual entries and evidence-derived assertions retain their existing calendar-day and source contracts.

## Temporarily ignore a device

The device detail screen includes an **Ignore this device until** row with a `CalendarDay` picker.
The control applies across the account. Raw observations remain stored, and local recording consent remains unchanged.
It changes history selection rather than remotely pausing the location service.

The ignored interval starts now and includes the selected day.
For example, November 8 means through the end of November 8 in the time zone where the user made the choice.
The stored choice retains the selected day, time zone, and resolved time boundary.
Later travel does not move that boundary. Earlier observations remain unaffected.

Automatic selection excludes the device during this interval, even with strong movement evidence.
An explicit source choice takes precedence over the ignore filter for its selected period.
This applies to existing and new choices, regardless of write or sync order.
The control and review preview explain this interaction without another confirmation step.

The user can change the end date or select **Resume now**.
Resume ends the interval going forward and preserves the elapsed ignored interval.
A separate undo action restores eligibility for the elapsed interval.

Expired intervals remain durable decisions.
Automatic selection filters late uploads by observation time, even after an ignore interval expires.
An offline device applies the shared decision after sync. The UI does not promise immediate remote control.
The existing permanent **Remove device** action remains available for lost, stolen, or replaced devices.

## Region agreement and movement

History assessment uses specific region identities from the full catalog, independently of the selected primary regions.
Derived history retains that geographic specificity before reporting groups the results.
Different coordinates in the same known region do not create a region-history conflict.
Those observations remain distinct records with their original coordinates.
Region agreement does not justify joining different devices into one physical trajectory.

Overlapping observations agree for reporting only when both their known catalog region and resolved recording day agree.
If their days differ, source selection determines the region and recording day together.
Strong source evidence permits automatic selection. Ambiguous recording-day conflicts use the existing review flow, which shows both dates.
Both devices retain their raw observations and original day assignments.

For example, two New York observations at 06:00 UTC on December 9 can carry December 8 and December 9 labels.
Their timestamps establish the overlap, but do not choose the local day that represents the user.
Selection never counts both days merely because their region agrees.

**Other** is a reporting group for non-primary regions or unresolved geography.
It is not a geographic identity that establishes agreement between devices.
For example, simultaneous Nevada and Oregon tracks remain distinct even when neither region is primary.
Selection resolves their competing evidence or exposes a conflict before reports group the results.
Elsewhere consumes the same selected history and uncertainty before it counts named visits.
For unchanged evidence and decisions, changing primary regions changes reporting groups without changing geographic agreement or source selection.

Coordinates outside the catalog remain geographically unresolved.
Equal unresolved values provide no evidence of geographic agreement.
Unresolved geography alone also does not establish a device conflict.
Materially divergent, overlapping tracks use the same evidence assessment and review rules.
Nearby points or isolated GPS noise do not establish a conflict.

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

### Initial assessment policy

[`MultiDeviceAssessment`](WhereCore/Sources/Devices/MultiDeviceAssessment.swift) implements the pure foundation.
Its inputs retain device identity, full-catalog geography, and resolved or unresolved recording-day assignments.
An unresolved assignment never uses the viewing zone as a fallback.
Production integration must supply effective geographic corrections before assessment, including explicit assertions of unknown presence.

Periods use half-open boundaries: the start is inclusive and the end is exclusive.
Each point has one second of bounded support.
Consecutive observations connect only across gaps of at most 30 minutes.
The resolver splits at observation and coverage boundaries before it clips results to a query.
The final point's bounded support retains its preceding anchor within the same coverage component.
With identical input context, narrowing a query cannot change its overlapping assessment.
Callers must supply adjacent evidence, including observations outside the displayed day or year.

[`RecordingEvidencePolicy`](WhereCore/Sources/Devices/RecordingEvidencePolicy.swift) owns the policy version, thresholds, units, and decision meanings.
The initial policy requires three independent fixes and accuracy of 250 meters or better for strong movement or stationary evidence.
Movement also requires ten minutes, one kilometer of accuracy-adjusted displacement, two corroborating advances, and coherent progress.
Stationary evidence requires twenty minutes of positive observations within the accuracy-adjusted dwell radius.
All intervening fixes participate in plausibility checks. Dense callbacks cannot hide a contradictory jump.

Matching known regions and recording days agree for reporting.
A geographic conflict requires repeated, separated observations whose uncertainty circles remain more than two kilometers apart.
Different region labels near a boundary remain uncertain. An isolated distant fix does not establish a geographic conflict.
A known recording-day disagreement remains independent of geographic distance.
Equal-timestamp observations all participate, so their identities cannot select an arbitrary geographic or day interpretation.

[`RecordingDayCoverage`](WhereCore/Sources/Devices/RecordingDayCoverage.swift) resolves whole-day periods from explicit calendar-context intervals.
It preserves repeated-date gaps and daylight-saving boundaries without requiring GPS throughout the day.
Its caller must establish a search period that contains every occurrence of the date.
Missing calendar context prevents a whole-day result. It does not invent coverage from the first and last GPS points.

The assessment tests cover synthetic travel, stationary tracks, noise, sparse data, threshold boundaries, repeated dates, and input permutations.
The pure policy remains inactive. Platform capture experiments and representative phone-journey measurements remain required before production activation.
The current capture adapter passes `CLLocation.timestamp` or a `CLVisit` arrival/departure timestamp into the sample.
Neither callback supplies the device's historical time-zone assignment.
A current zone or a later zone-change notification cannot establish every intervening historical context.
Slice 4 must validate context capture and recovery before it changes observation storage.

### Regular homes and temporary bases

The user can optionally specify a precise regular home location in each primary region.
They can also specify dated temporary bases, such as a different New York hotel for each trip.
They choose a place on a map or save it during history review.

A regular home has a start boundary and remains valid until the user changes or ends it.
A temporary base requires an end date. Ongoing home validity uses an explicit representation, not an invented future expiration date.
Changing or ending a home preserves its earlier definition for historical observations.

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

The choice selects a source for the period. Later eligible observations from that source can change the resulting history and totals.

**Return to automatic** reverses the explicit choice for the selected period.
The resolver can then reconsider eligible observations from other devices.
Ignore intervals apply again by observation time, including elapsed intervals whose end date has already passed.
Choices for other periods remain intact.

### Removal of a selected device

Permanent device removal limits eligible GPS observations even when an explicit source choice selects that device.
Observations before the removal cutoff remain eligible under the other history rules. Observations at or after the cutoff remain excluded.
This precedence applies regardless of the write or delivery order of the removal and source choice.

Removal preserves the source choice instead of returning its affected period to automatic selection.
Other devices do not fill the resulting gap.
The affected choice appears in the review flow for the portion at or after the cutoff.
The user can select another device for that portion or return it to automatic selection.
Earlier portions of the choice remain intact.

### Saving a reviewed choice

The save proposal retains the reviewed period, relevant evidence and decisions, and causal context.
It also retains the full policy version, query context, and data generation until the guarded save completes.
Reassessment and the decision write occur inside the same guarded transaction.
The transaction checks the expected data generation, relevant read state, and current compatibility permit.
Whole-day saves also require unambiguous coverage from the recorded calendar context used in the preview.
If relevant inputs changed, reject the proposal and return the refreshed issue without applying the choice.
Known incompatibility follows the update gate instead of permitting the write.

The new operation uses the reviewed causal context. It never silently adopts newer decisions as intentional predecessors.
Unrelated imports do not require another user review when the relevant inputs remain unchanged.
Decisions that arrive after commit retain their causal relationship to the reviewed decision set.
Incompatible concurrent choices remain available for resolution under the existing merge rules.
The [sample-correction coordinator](WhereCore/Sources/DataResolution/SampleCorrectionCoordinator.swift) provides an existing guarded review-and-write pattern.

This transaction protects local state. It cannot establish knowledge of unreceived changes on other devices.
In a permitted account scope, Save confirms durable local storage. Normal CloudKit mirroring handles synchronization.
The save operation adds no separate online-confirmation requirement or pending-approval state.
[Offline compatibility](#offline-compatibility) defines cached access, version admission, and the update gate.

### Evening reminders and guided review

Each device schedules one combined evening local notification for missing history and unresolved issues, including device conflicts.
It retains the existing category enablement choices and the user-selected reminder time.
The separate daily region-summary notification keeps its own purpose and schedule.

Reminder preferences remain local and default to enabled.
Each phone uses its own preferences and available issue state, subject to system notification permission.
Both phones can notify about the same work. Delivery requires no account-wide notification owner or duplicate suppression.
Disabling reminders on one phone does not change recording, history selection, or another phone's reminder preferences.
Unresolved issues remain accessible in the main issue list.

The combined notification describes the remaining work and its counts.
Older unresolved issues remain eligible even when today's history is complete.
Issue discovery covers all years containing history, independently of the current year or the year selected in the UI.
Year boundaries never expire unresolved issues. A December issue remains eligible for reminders in January and later years.

Late imports can add historical issues to this same scope.
The main issue list includes this historical work.
Reminder counts respect the existing category enablement choices.

Confident automatic selections do not generate issue notifications. Their explanations remain available in the app.
Changes to history or issue state refresh or cancel pending reminders.

Notification references retain each issue's original review scope, historical year, and query context as well as its current identifier.
Opening a notification uses that context instead of substituting the current or selected year.
A notification opens a guided flow for the issues that it raised:

1. Reassess the original review scopes and retain their remaining relevant issues.
2. Show one issue with its date, explanation, available actions, and progress through the queue.
3. Offer **Save and continue** and **Skip for now**. A skipped issue remains unresolved.
4. Validate the reviewed inputs inside the guarded decision-write transaction.
5. If they changed, reject the proposal and show the updated issue before the user commits a choice.

The user can close the flow at any time. Completed choices remain saved.
The issues bar button provides access to the remaining issues and a **Review remaining** action.
Both entry points use the same resolution screens and actions.
Unrelated new issues stay in the main list rather than extending the notification queue indefinitely.
Successful reassessment must find no remaining relevant issues before the flow reports that its work is resolved.

#### Queue reassessment after splits and merges

The queue follows the original concern and affected periods through reassessment. A derived issue identifier alone does not define that work.
Changed identifiers or boundaries never count as resolution by themselves.
Reassessment includes current relevant evidence and decisions, including newly arrived evidence from another device.
It does not restrict assessment to the device set or observations available when the notification was created.

If an issue splits, retain each unresolved part within the original scope. Omit parts that no longer require action.
If issues merge, show the relevant combined context while preserving the original review scope.

Overlapping queued scopes review the same remaining work once.
A merge never adds intervening gaps or adjacent periods to the scope of a saved choice.
Unrelated issues and work outside the original scope remain accessible from the main issue list.
Queue progress reflects the current remaining work after reassessment.

Each proposed resolution previews its actual affected periods and decisions.
Changes remain within the reviewed scope. A broader choice requires an explicit scope change and review of the updated preview before save.
The guarded write revalidates that scope and its relevant inputs, including changes caused by a split or merge.
Reassessment and queue updates never delete raw observations, discard unresolved decisions, or extend a saved choice automatically.

A failed reassessment leaves the work pending and exposes retry instead of reporting that all issues are resolved.
Skipped work remains unresolved and accessible from the main issue list.

#### Device status in the evening reminder

The combined evening reminder also includes device status issues when expected data for recent selected periods remains unavailable.
These issues use the local issue-alert preference and the same bounded review flow.
Opening one shows the affected period, device, last available observation, reported activity, and reported recording status.
Unknown values remain explicit. Reported status and activity retain their timestamps.

The guidance asks the user to open Where on that phone and check recording, permissions, and sync.
The user can also review the affected period or change its source choice through the existing controls.

The notice describes missing updates without claiming a proven upload failure.
An absence of new GPS points alone cannot establish failure, and a quiet, adequately recorded day needs no device status issue.
Advisory check-ins do not prove that all observations arrived or that recording still works.
Assessment distinguishes source-device evidence from the receiving phone's own unavailable or failed sync.
It never treats the receiver's stale view as proof that the source stopped recording.

The check concerns devices needed for recent selected periods.
An old historical choice does not create an indefinite expectation that its device keeps reporting.
Missing historical data remains available for review under the existing issue rules.
The warning never switches sources, changes recording consent, fills selected-track gaps, or creates location evidence.

Fresh evidence reassesses the device status issue and its pending reminder.
A new check-in can resolve an activity concern without proving that missing observations arrived.
Any remaining history issue keeps its own resolution condition.
Opening the device screen alone does not resolve the issue. Skipped work remains in the main issue list.
Define recent-period eligibility, evidence requirements, freshness thresholds, and recovery conditions before this reminder activates.

## Late observations and historical changes

A late upload adds raw evidence. It does not directly add every reported region to the recorded day.
Selection occurs before `DayAggregator` combines effective region presence.
For example, a phone left in New York cannot add New York to a California trip merely because it uploads later.

Explicit period choices remain in force as other devices upload observations.
Automatic periods apply ignore intervals by observation time, including after expiry.
Explicit source choices retain precedence over those intervals.
For a given full policy version, automatic periods use the combined available evidence regardless of upload order.

Later eligible observations from the selected device contribute within the chosen period, including where the reviewed track had gaps.
They can add region presence and change totals while the source choice remains effective.
The reviewed inputs validate the save. They do not restrict future evidence to the observations available at that time.

Ordinary changes to history or totals require no new confirmation and do not reopen the source choice.
If reassessment discovers an unresolved issue, it enters the normal issue list and enabled evening reminder.
Other devices remain excluded from the selected period, including any remaining gaps.

Good late evidence can fill missing periods or automatically correct earlier automatic history when the evidence is strong.
The resulting explanation remains inspectable.
Genuinely ambiguous evidence produces a review issue instead of confident presence in every competing region.
A previously populated day is not automatically final. Explicit choices preserve the selected source while its evidence can become more complete.
Every affected output refreshes after reassessment.

## Data and decision boundaries

Raw observations remain the durable evidence.
Backups and diagnostic review retain original coordinates, timestamps, accuracy, source, and installation identity, plus recording-day assignments and their time-zone context.
Automatic selection does not erase observations or rewrite their device identity.
Existing explicit removal, reset, and deletion operations retain their separate contracts.

Automatic decisions are derived results.
Their evidence and full policy version explain the result and permit reassessment after late sync or a policy change.
Derived results and caches carry that full version.
A policy update invalidates affected cached results and reassesses automatic history without rewriting raw observations or durable user choices.
User choices are durable decisions with a logical recording-day scope or fixed time-range boundaries.
They retain their authoring data-semantics version, immutable identity, and reviewed causal context.
They take precedence over automatic selection and remain reversible.

Device selection applies to automatic GPS evidence.
It does not override manual entries, authoritative day overlays, or evidence-derived assertions.
Existing per-sample corrections continue to affect eligible observations.
A correction cannot bypass an applicable source choice, ignore interval, or removal cutoff.
Corrections remain stored when their observations are excluded.
Geographic attribution retains specific catalog regions where available, before primary-region reporting groups them under Other.
Explicit assertions of unknown presence retain their meaning. Catalog lookup does not replace them with inferred named regions.
Automatic GPS requires device attribution before history selection.
Pre-release conversion repairs historical missing attribution before the new data contract activates.

Every consumer uses the same effective history contract.
Reports, Elsewhere, widgets, reminders, issue scans, exports, and relevant App Intents use the same policy version on a device.
They agree for identical evidence, decisions, and query context after local writes, remote imports, user choices, and policy updates.
Different compatible policy versions can produce different automatic history, totals, and issues across devices.
They preserve the same shared meaning of durable user choices and controls.
Raw track review and lossless backups remain available separately.
Flight and movement inference preserve device boundaries.
An unresolved source or recording-day conflict remains visible to consumers instead of silently becoming a confident combined history.
Counts and report completeness follow the unresolved-history policy below.

### Totals and exports with unresolved history

Totals include presence supported by resolved history, including valid user choices and strong automatic selections under the existing policy.
If a conflict remains ambiguous, require user input before assigning its disputed region or recording day.
Do not infer a winner or count every competing region to fill the gap.
Unresolved contributions stay excluded until resolution. Raw observations and competing decisions remain intact.

Resolved presence elsewhere on the same recording day still contributes normally.
For example, an unresolved California/New York conflict contributes neither disputed presence.
A separate resolved California observation that day still counts once for California.
The day remains incomplete because the unresolved period can affect its history.

Affected reports show **Incomplete** and the distinct affected recording days that need review.
Several conflicts on one day count once in that indicator.
A partly resolved day can contribute to region totals and also appear in the review count.
Unresolved day assignments remain separately visible when their affected recording days cannot yet be established.
An unresolved recording-day conflict marks each candidate day incomplete and contributes no disputed region-day.
Turning reminders off never changes report completeness or export eligibility.

Reports, Elsewhere, widgets, summaries, reminders, and relevant App Intents apply the same contribution and completeness rules.
A surface must expose incomplete status with its counts or withhold the counts when it cannot express that status.
Do not convert an unresolved source conflict into Other to make the report appear complete.
Existing manual assertions, authoritative overlays, and explicit unknown-geography assertions retain their own contracts.

History-report exports require resolved history for the exported scope.
Unresolved selection conflicts, recording-day conflicts, or day assignments block export when they can affect that scope.
The export action directs the user to review those periods before producing the report.
Unresolved work outside that scope does not block an otherwise eligible export.
Eligibility and exported content use the same local history snapshot.

A failed or incomplete assessment blocks export with an observable error or review state.
Lossless backups remain available and preserve raw evidence and durable decisions.

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
An ignore interval and an explicit source choice do not conflict merely because their periods overlap.
The explicit choice takes precedence for its period after merge, regardless of their write or delivery order.
Other shared controls define their merge semantics before persistence ships.
CRDTs provide useful models for this behavior, including a multi-value register that retains concurrent choices until a subsequent choice replaces them.
See [INRIA's multi-value register](https://concordant.gitlabpages.inria.fr/software/c-crdtlib/c-crdtlib/crdtlib.crdt/-m-v-register/index.html).
[`HistoryDecision`](WhereCore/Sources/Devices/HistoryDecision.swift) uses explicit predecessor identities rather than revision prefixes.
Each operation has a UUID identity, author, normalized periods, action, predecessor set, and authoring semantics version.
Retries and imports retain the original identity and payload. A new decision receives a new identity.
No per-device counter determines causal knowledge or chooses a concurrent winner.
This plan does not select a general CRDT framework.

Counters describe decisions actually received and incorporated.
Receipt of revision 50 before revision 49 cannot imply knowledge of every revision through 50.
Counter allocation, persistence, and recovery must prevent reuse after crashes, backup restore, or reset.
Reusing a recording identity does not permit reuse of an operation identity for a new decision.
The causal persistence design defines safe recovery before new decision writes resume.
Dates remain useful for display and diagnosis. Wall-clock ordering does not decide between incompatible concurrent user choices.

[`HistoryDecisionResolver`](WhereCore/Sources/Devices/HistoryDecisionResolver.swift) computes explicit predecessor closure for each received operation.
Missing predecessors make the affected periods incomplete until those dependencies arrive.
A replacement supersedes ancestors only where its own periods apply.
The resolver rejects identity collisions, empty scopes, cycles, and unsupported major contracts.
Compatible minor and patch versions preserve this decision interpretation.
The [initial PlusCal model](Specifications/MultiDeviceDecisions/README.md) checks bounded delivery, concurrent choices, and replacement scope.
It does not establish durable identity recovery, guarded writes, or server acceptance.

Raw observations merge by stable identity and retain provenance.
Automatic selection recomputes from the available evidence and full policy version instead of accepting a remotely chosen derived winner.
Shared observations and decisions converge across compatible clients after all relevant records arrive, regardless of duplicates or delivery order.
Equal automatic history additionally requires identical full policy versions and query context.
Sync status reports observable facts, such as the last successful operation and known pending changes.
It never promises that every device is fully current.

## Compatibility

Data-semantics versions use `major.minor.patch`, separate from the app version.
The full data-semantics version also identifies the resolver policy.
Each dataset carries a monotonic required major version for its data and decision contract.
Cloud-backed datasets share this requirement through the account. Local-only datasets retain it locally.
The gate blocks clients that cannot honor that contract.
Minor and patch differences alone never trigger the incompatible-data gate.

| Component | Meaning | Compatibility effect |
| --- | --- | --- |
| Major | Incompatible stored-data structures or interpretation of shared decisions. | Activation advances the required major and gates clients that cannot honor it. |
| Minor | Compatible improvements, including new automatic-selection heuristics. | Clients remain compatible. Automatic results can differ. |
| Patch | Bug fixes within the existing shared contract. | Clients remain compatible. Automatic results can differ. |

Within a major version, clients preserve the shared meaning of observations, explicit source choices, ignore intervals, and causal decisions.
A new control that older clients cannot honor requires a major change.
An older client cannot ignore a saved choice because it lacks that feature.

Each build uses its current resolver. It does not retain every earlier algorithm implementation.
The account does not pin an active minor or patch version.
Compatible versions can produce different automatic history, totals, and issues, even from identical inputs.
Those differences can persist while devices run different policy versions.
Exact history equality requires identical evidence, decisions, full policy versions, and query context.
Regression scenarios preserve established automatic behavior where practical and check the shared decision contract across supported versions.

### Dataset scope

Cloud-backed datasets use account verification and guarded server confirmation for shared initialization and major activation.
Local-only datasets initialize and advance their required major through guarded local transactions.
They require no iCloud account or network connection. The default Where Development dataset uses this local path.
Both paths validate stored data and backup imports. An unsupported dataset enters the compatibility gate.
An unsupported backup fails admission without changing the active dataset.

The dataset's configuration determines this distinction, independently of network availability or the current process's storage adapter.
A cloud-backed dataset remains subject to account verification while offline.
A widget that reads its published local files remains subject to that dataset's compatibility gate.
A local compatibility check never supplies a shared-account permit.

### Account verification and initialization

For cloud-backed datasets, account verification distinguishes three states:

| State | Shared-data initialization and upgrade behavior |
| --- | --- |
| Unknown | Verification is incomplete or failed. Do not initialize or advance the required major. Expose a retry state. |
| Verified existing | Adopt the required major from verified shared account state. Advancing it follows the eligibility or explicit-upgrade rules. |
| Verified new | Initialize the current supported major through guarded account initialization. |

An empty local store does not establish a new account.
Neither an absent compatibility record nor completion of one sync operation establishes account newness.
Verification uses shared state for the current account and store.
Legacy data without compatibility metadata remains an existing-account case.
Its bootstrap path establishes the applicable major without bypassing upgrade eligibility or explicit consent.

Initialization must handle simultaneous setup on multiple devices.
A concurrent initializer adopts the established shared account state instead of overwriting it with its preferred major.
Incomplete or failed verification remains unknown and preserves any previously observed required major.
The implementation defines the shared evidence and guarded creation protocol before activation.
The offline policy permits continued access only through valid cached verification for the same account and store.

### Major upgrades and access

The incompatible-data state uses direct copy:

> **Update Where to continue**
>
> Your data uses a newer format that this version of Where does not support.

A failed compatibility check has a separate retry state. A network error does not claim that the app needs an update.
The gate covers foreground access, background work, relevant App Intents, and published widget output.
It rejects writes through revoked scopes and withdraws their misleading output.
An old backup, stale response, or older client cannot lower the required major version.

The required major advances when incompatible behavior activates. A routine app update alone does not advance it.
Minor and patch updates do not require shared-data upgrade eligibility or the explicit upgrade action.
For cloud-backed datasets, automatic major-upgrade eligibility requires a meaningful contribution to effective history within the preceding **15 days**.
Explicit source selection for a period within that window also qualifies the device.
The window uses the observation or selected period dates, not the upload date or the time of the selection action.

Local recording enablement, raw ping volume, and excluded observations do not establish eligibility.
Redundant observations that never contributed useful history do not qualify an idle device.
Useful stationary observations do qualify. Movement is not required.
Old observations uploaded today do not make their device a recent contributor.

Any capable device can offer an explicit **Upgrade shared data** action to advance the required major.
The explanation states that apps which cannot honor the new major will need an update.
This action supports replacement phones, long absences, and incomplete recent history without a 15-day waiting period.
An ineligible device continues with the current required major when it supports that contract.

The recent-contributor rule prevents incidental automatic major upgrades from unused devices.
A legitimate major upgrade can still require updates on other active devices because the compatibility boundary applies to the account.
No device needs exclusive recording ownership to perform an upgrade.

#### Beta use across devices

If a user uses Where Beta, every device that accesses the same history must use Where Beta.
A beta update can require updates on other devices before they can continue.
This support policy adds no protocol to verify the build channel on every device.
The ordinary upgrade eligibility, server confirmation, compatibility gate, and update notification rules still apply.
A beta can activate a new major before an App Store build supports it.

Returning to the App Store build requires a release that supports the dataset's current required major.
Installing an older App Store build cannot downgrade the history.
Setup and update guidance explain the beta requirement and the condition for returning to the App Store build.

#### Local notification when an update is required

When this phone detects an unsupported required major, request a local update notification without waiting for the evening reminder.
An incompatible incoming record also triggers the gate when its version establishes the unsupported contract.
Use **Update Where to continue** as the title.
The notification opens the update screen, which offers the appropriate update destination for the installed build.
If recording was active, the message explains that recording on this phone is paused until an update restores compatible access.
The message must not claim that recording stopped when the user already had it off.

This operational alert is separate from the evening reminder preferences and schedule.
Use one owned notification request and local tracking to suppress repeated alerts during the same incompatible state, including across relaunch.
Do not schedule a repeating alert. Repeated checks must not produce a notification storm.
Notification handling remains available after the shared-data scope retires and does not read incompatible history.

Delivery depends on existing system notification permission and settings.
If permission is unavailable or scheduling fails, keep the update gate visible and expose the notification limitation.
Do not delay the gate or request permission from a background callback.
The unsent alert remains eligible for retry while the gate stays active. Successful scheduling does not prove delivery.

The app can notify only after this device learns about the incompatibility and can run the scheduling code.
It cannot promise immediate warning on an offline or suspended phone.
Apple documents the permission and delivery behavior under [notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) and [local scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

After compatible access resumes, remove the owned pending or delivered update alert and clear its suppression state.
Changing accounts also clears the old account's notification without authorizing access to the new account.
Revalidate the current gate when the user opens an old notification.

### Offline compatibility

The following account-verification and cached-access rules apply to cloud-backed datasets.
Local-only datasets use the local transactions and compatibility checks defined under [Dataset scope](#dataset-scope).

The first version uses guarded local saves and the existing automatic CloudKit mirroring path for shared choices.
Save confirms local durability. It does not confirm server acceptance or knowledge of every device's current state.
The UI reports observable sync activity without a separate per-choice approval workflow.
The first version adds no offline-draft store or server-confirmed decision-publication protocol.
Future versions can add stronger confirmation at the save boundary because review proposals remain separate values.

Successful verification permits offline access for the same account and store while the app supports every known compatibility requirement.
The cached permission has no time-based expiry solely because the phone remains offline.
It does not authorize account initialization, a major upgrade, or a different account or store.
The client retains the highest observed required major across failures, relaunch, and backup import.
A failed server refresh does not by itself establish that the account changed.

Before an online check can observe a higher requirement, invalidate its durable cached grant.
The running process retains its previously verified same-account proof for a completed transient network failure.
Restore durable offline access only after every pending verification has completed safely.
If the app quits during verification, the next launch requires one successful online check before reopening shared history.
This also prevents a failed save of a newly observed requirement from restoring an older grant after a crash.

| Local knowledge | Access policy |
| --- | --- |
| Compatible account and store with valid cached verification | Continue locally consented recording, cached history reads, and guarded local saves while offline. |
| A refresh fails for that same verified account and store | Retain cached access and show sync uncertainty. Do not treat the failure as an update requirement. |
| The app quits while an online compatibility check is pending | Require one successful online check after relaunch. Preserve consent and stored history while access is paused. |
| No valid verification exists, or the account/store identity changes or cannot be established | Require successful verification before activating recording or shared-data access. Expose retry without initializing from local emptiness. |
| An unsupported major becomes known | Retire the shared-data scope, stop automatic capture, reject further shared edits, and withdraw misleading output. Require an app update. |
| A compatible app satisfies the ordinary activation checks after the gate | Create a fresh scope and permit. Resume only the recording allowed by local consent and system permissions. |

A known incompatible requirement immediately revokes cached access. A stale response or lower cached major cannot restore it.
The first version captures no new raw observations while this gate is active and adds no separate buffer for them.
This can leave a recording gap until the user updates. The gate and update notification explain that consequence.
The pause preserves local recording consent, stored observations, decisions, and already accepted durable retry data.
It must not use a recording-off or reset path that discards that evidence.

Resumption requires compatible admission of retained data and a fresh scope, not merely dismissal of the notification.
Recovery never replays retained retry data into another account.

Cancel pending history reminders and summaries owned by the retired scope, and withdraw its widget output.
Keep the update notification and update screen available independently of that scope.
Minor and patch differences retain their agreed compatibility behavior.

Readers validate a decision's authoring semantics before applying it.
Minor and patch differences alone cannot reject a shared decision within its supported major contract.
Each future major change defines explicit handling for existing and late-arriving earlier decisions before activation.
Compatible migrations preserve their meaning and identity.

If a decision cannot be interpreted safely, retain the original record and require a new review in a compatible app.
Its affected history remains unresolved instead of silently returning to automatic selection.
Version one does not attempt automatic replay of choices whose meaning is uncertain.

Local durability and forced app updates do not prevent every offline upgrade race.
Causal metadata cannot notify an offline older app about a major upgrade on another device.
Pending exports can arrive before the app observes the new required major.
The protocol handles those records through version admission rather than assuming that application code can gate every export.

The current [SwiftData store](WhereCore/Sources/Persistence/SwiftDataStore.swift) uses automatic CloudKit mirroring.
Apple documents separate local saves, exports, and imports in [TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer).
A connection check followed by a local save does not order that write against a concurrent major upgrade.

### Major activation and rollout

For a cloud-backed dataset, major activation requires online account verification.
A guarded, server-confirmed advance of the shared required major must precede incompatible behavior.
An offline cache or a local compatibility-record save cannot authorize activation.
This confirmation applies to the major upgrade, while ordinary decisions retain their guarded local-save contract.
If confirmation fails or its outcome is uncertain, reverify shared state before retrying activation. Never assume that the server rolled back.

Metadata and incompatible records can reach another device in either order.
Readers must identify an unsupported contract before interpreting its payload, even when the required-major record arrives later.
Either observation enters the same gate. An incompatible record never becomes a compatible default or apparently complete history.
Version admission also covers late observations and decisions authored before an offline client learns about the upgrade.
Each major defines their preservation, safe conversion, or explicit repair before activation.

The initial rollout establishes compatibility-aware readers and the required pre-release data conversion before exposing incompatible data.
Pre-foundation clients must upgrade or be excluded from the replacement dataset through the rollout procedure.
A sync-completion event or an advisory device check-in cannot establish this condition.
Define the guarded server operation, record version representation, and rollout procedure in the compatibility slice before incompatible writes ship.
The formal models must check both delivery orders and the actual store boundaries.

## Required scenarios

| Evidence or action | Expected behavior |
| --- | --- |
| Both phones report different coordinates within the same known catalog region and recording day | No region-history conflict, including outside the primary set. Preserve both sets of observations. |
| Simultaneous tracks occupy Nevada and Oregon while neither region is primary | Retain both geographic identities. Select from strong evidence or expose a conflict before reporting Other or counting Elsewhere visits. |
| Both phones report coordinates outside the catalog | Keep geography unresolved. Infer neither agreement nor conflict from fallback values alone. Assess the tracks for independently supported divergence. |
| The user changes primary regions without changing evidence or decisions | Regroup reports without changing geographic agreement or source selection. |
| A manual assertion or sample correction explicitly specifies unknown presence | Preserve that asserted meaning. Do not replace it with a named region through catalog lookup. |
| One phone travels while another repeatedly reports from home | Select the moving phone where evidence is strong. Explain the selection. |
| Several phones remain at home while one accompanies the user | Assess evidence without a device-count vote. |
| The user changes phones during the day | Permit different selected devices in different periods. |
| An observation has a resolved December 8 recording day and is later viewed in another time zone | Keep it on December 8 in history. Preserve its timestamp and recording time-zone context. |
| A callback arrives after midnight or after a device time-zone change | Assign the day from the observation time and its device-local context. Do not substitute the delivery date or current zone. |
| The observation-time zone cannot be established | Preserve the raw observation and expose unresolved day assignment. Do not invent a day or publish apparently complete history. |
| Overlapping observations have different device-local date labels | Establish overlap from full timestamps and bounded track coverage. Select the region and recording day together through strong evidence or user review. Date labels cannot bypass source-choice coverage. |
| Overlapping observations agree on the region but disagree on the day, without strong source evidence | Keep both candidate days incomplete and exclude the disputed contribution. Show both dates in the existing review flow. Preserve both raw assignments. |
| Observations share a UTC calendar date but cover separate periods | Do not infer overlap or a conflict from the shared UTC date alone. |
| A whole recording day spans daylight-saving or date-line changes | Use the selected device's recorded calendar context. Do not assume a fixed 24-hour window. |
| A device's recorded date progresses from December 8 to December 9 and back to December 8 | A December 8 source choice covers both December 8 portions. Keep the intervening December 9 portion outside that choice. |
| A selected whole day has a GPS gap but its recorded calendar context is known | Keep the choice exclusive through the covered gap. Missing GPS alone does not prevent the whole-day choice. |
| Missing recorded calendar context makes a proposed whole-day choice's coverage ambiguous | Require clarification before save. Offer the existing fixed time-range choice without inventing whole-day boundaries. |
| The user chooses a fixed time range while some recording-day assignments remain unresolved | Save under the ordinary guarded-write rules. Keep those assignments unresolved and apply the existing completeness and export rules. |
| A historical archive lacks recording-day context | Resolve it through offline conversion with supported metadata or explicit mappings. Preserve existing assignments and original timestamps. |
| The app updates or relaunches normally | Preserve the installation's identity and local recording consent. |
| The user imports a backup through merge or replace | Preserve local identity and consent. Retained historical records keep their original provenance. |
| A historical archive contains GPS without device attribution | Convert it offline with explicit source-device mappings before import. Preserve observations and existing identities. |
| Conversion lacks a required source-device mapping | Stop conversion without modifying the input. Do not guess a device or accept unattributed GPS. |
| Unattributed GPS reaches backup import or a remote-store read under the new contract | Expose an admission failure. Preserve the original evidence for repair without silently excluding it or accepting incomplete history. |
| The user explicitly resets the app | Create a new identity and request recording consent again. Apply the existing data-reset contract. |
| A removed device rejoins | Create a new identity and request consent again. Keep the previous identity removed. |
| The user reinstalls Where or restores the same phone | Reuse a surviving valid Keychain identity, or create one through setup if absent. Request recording consent again. |
| The identity's Keychain item is inaccessible | Show retry or unlock state. Do not treat the item as absent or create a replacement identity. |
| A system backup restores or transfers to another physical phone | Create a new identity and establish local consent. Keep historical records attributed to their original devices. |
| Recovery retains an identity but encounters older counter state | Prevent operation-identity reuse. Complete safe recovery before new decision writes resume. |
| One device reports and another remains silent | Assess the available track without inventing a stationary competitor. |
| Two devices travel in different regions during the same period | Request review unless independent evidence supports automatic selection. |
| A sparse track or inaccurate boundary point suggests movement | Preserve uncertainty. Do not classify it as strong movement evidence. |
| An unresolved California/New York conflict has no separately resolved presence | Exclude both disputed contributions and require user input. Mark the report incomplete and block history-report export for the affected scope. |
| The same day also has a resolved California observation | Count California once from the resolved evidence. Keep the disputed contribution excluded and the day marked for review. |
| Several conflicts affect one recording day | Count that day once in the review indicator. Preserve every unresolved concern. |
| The user disables issue reminders while conflicts remain | Preserve incomplete status, excluded contributions, and the affected export gate. Keep the issues accessible. |
| A widget or intent cannot express report incompleteness with its counts | Withhold the counts instead of presenting them as complete. |
| A history-report export covers a resolved period while another period remains unresolved | Permit the unaffected scope after a successful assessment. Use the same snapshot for eligibility and exported content. |
| Export assessment fails or remains incomplete | Block the history-report export and expose the failure or remaining review. Do not treat unavailable assessment as no conflicts. |
| The user creates a lossless backup while history conflicts remain | Preserve the raw observations and durable decisions. Keep backup export available. |
| Devices disagree throughout a car, train, or plane journey | Review one continuous issue and preview an exclusive period choice. |
| The explicitly selected device has a gap | Preserve the gap instead of filling it from another device. |
| Duo is selected for December 8 and removed at noon | Keep eligible morning observations and the saved choice. Exclude Duo observations at or after noon, preserve the afternoon gap, and show that portion for review. |
| A source choice and its selected device's removal arrive in either order | Apply the removal cutoff without rewriting the choice or selecting another device automatically. |
| A removed selected device uploads observations late | Assess eligibility by observation time against the cutoff. Retain eligible earlier observations and exclude those at or after removal. |
| The user selects another device or returns the affected portion to automatic after removal | Apply the reviewed change only to that portion. Preserve earlier choices, removal cutoffs, and raw observations. |
| A per-sample correction targets an observation excluded by an applicable source choice, ignore interval, or removal cutoff | Retain the correction without restoring that observation to effective history. |
| A source choice overlaps a manual entry, authoritative overlay, or evidence-derived assertion | Apply the source choice only to automatic GPS. Preserve the other source contracts. |
| The user ignores a device after explicitly selecting it for a period | Keep the explicit choice effective. Exclude that device only from automatic selection within the ignored interval. |
| The user explicitly selects an ignored device | Apply the exclusive choice for its period. Explain the ignore interaction without another confirmation. |
| Different devices independently create an ignore interval and an overlapping source choice | Retain both controls. Apply the explicit choice for its period without a conflict from this overlap or delivery order alone. |
| The user returns a historical period to automatic after its ignore interval expires | Reapply the original ignore interval by observation time. Preserve raw observations and choices for other periods. |
| The user resumes an ignored device before the chosen end day | End the ignore interval going forward. Preserve its elapsed portion. |
| An ignored device uploads after the ignore interval expires | Apply the interval to automatic history by observation time. Honor explicit source choices and preserve raw uploads. |
| Late observations affect automatic history | Reassess the evidence. Permit strong corrections and expose genuine ambiguity. |
| Late observations from another device conflict with an explicit source choice | Preserve the explicit choice and exclude the other device for that period. |
| The selected device uploads more observations for a reviewed period | Include eligible observations and refresh history and totals. Keep the source choice and require no new confirmation for changed results alone. |
| Late selected-device observations reveal an unresolved issue | Keep the source choice effective. Show the issue through normal review and enabled evening reminders. |
| The user changes a source choice or returns to automatic | Rebuild effective history for the affected period while retaining raw observations. |
| The user selects a new home or a different hotel | Apply the place to its validity period without silently rewriting earlier context. |
| Two phones enable evening reminders | Each schedules one combined reminder from its local preferences and available issue state. Both can notify about the same work. |
| The user disables reminders on a secondary phone | Preserve recording and history selection. Keep issues accessible and leave the other phone's reminder preferences unchanged. |
| The user configures an additional or replacement phone | Show local reminder settings with enabled defaults, separately from recording consent. Permit changes during setup and later in Settings. |
| Recording is off on a phone with reminders enabled | Schedule eligible reminders independently of recording consent, subject to system notification permission. |
| Expected data from a device needed for recent selected periods remains unavailable | Include a device status issue in the combined reminder under the local issue-alert preference. Show the evidence and suggest checking that phone. |
| A quiet device has an adequately recorded day | Do not infer an upload failure or create a device status issue solely from absent new GPS points. |
| The receiving phone cannot refresh shared data | Expose its own sync uncertainty. Do not assert that another device stopped recording from the stale view. |
| A device selected only for old history stops reporting | Do not require continued reporting solely because of that old choice. Keep any missing historical data reviewable. |
| A fresh check-in arrives before missing observations | Reassess the activity concern without treating the check-in as proof of complete history. Preserve any unresolved history issue and source choice. |
| The user opens or skips an unresolved device status issue | Keep it accessible. Opening or skipping the screen alone does not resolve it. |
| The user exits the notification flow after resolving one issue | Retain the saved choice and expose the remaining issues through the bar button. |
| An unresolved December issue remains when January starts | Keep it in historical issue discovery, the issue list, and enabled reminder counts. Do not expire it at the year boundary. |
| A notification references an older year while another year is selected | Refresh and open the referenced historical period with its query context. Do not substitute the current or selected year. |
| A late import creates an issue in an older year | Include it in historical discovery and future enabled reminders. Keep an already-open notification queue bounded to its original work. |
| Another device resolves an issue before the notification opens | Reassess its original scope. Omit it only when no relevant issue remains. |
| A queued issue changes identifier while its disagreement remains | Retain the work through its original review scope. Do not report resolution from an identifier change. |
| A queued conflict splits into several conflicts | Include each unresolved part within the original scope. Keep resolved portions complete and update progress. |
| Queued conflicts merge with each other or adjacent work | Review overlapping work once with the relevant context. Do not expand saved choices across gaps or outside the reviewed scope. |
| New evidence changes the devices involved in the original disagreement | Reassess that concern using the new evidence. Do not lose it through a frozen device set. |
| A split or merge changes the proposed resolution before save | Reject the stale proposal through the guarded write. Show the updated scope and preview before another save. |
| The user explicitly expands the resolution period | Preview the broader effect and relevant choices. Save only after review and guarded revalidation of that scope. |
| Queue reassessment fails | Preserve pending work and expose retry. Do not show an all-resolved state. |
| Relevant evidence or decisions change after the review opens | Reject the stale proposal and show the refreshed issue without applying the choice. |
| The guarded write detects changed inputs or a retired data generation | Abort the effective decision write. Preserve the reviewed causal context and require a valid current review. |
| A known compatibility change revokes the write permit | Reject the write and follow the compatibility gate. |
| An unrelated import leaves the reviewed inputs unchanged | Permit the valid choice without another user review after transaction revalidation. |
| An incompatible decision arrives after the local commit | Preserve its causal relationship to the reviewed decision set. Retain concurrent choices for resolution instead of silently replacing them. |
| A permitted account scope saves a choice while offline | Commit the guarded local write and use normal mirroring. Do not claim server acceptance. |
| A local-only Development dataset starts or activates a supported major without a network connection | Initialize or advance its required major through a guarded local transaction. Require no shared-account verification. |
| A local-only dataset imports a backup with unsupported semantics | Reject the import without changing the active dataset. Local operation does not bypass format admission. |
| A cloud-backed dataset is offline, or a widget reads its published local files | Retain the shared-account compatibility requirements. Local access does not make the dataset local-only. |
| A verified compatible phone remains offline for a long period | Keep recording, cached reads, and guarded local saves available without a time-based expiry. Preserve local consent requirements. |
| Verification refresh fails for the same account and store | Keep valid cached access and expose sync uncertainty. Preserve the highest known major without sending an update alert. |
| The account changes or valid verification is unavailable | Require verification before activating recording or shared-data access. Do not reuse another account's permit. |
| An older client observes an unsupported required major | Pause capture and shared-data access, retire its scope, and request an update notification. Preserve prior evidence and local consent. |
| The gate closes with accepted observations still in the durable retry queue | Preserve the queue for compatible admission after recovery. Do not discard it through a recording-off or reset operation. |
| The phone detects the same incompatible state repeatedly or after relaunch | Keep the gate active and suppress repeat update alerts. Do not schedule a repeating notification. |
| Notification permission is denied or update-alert scheduling fails | Keep the in-app gate and recording pause effective. Expose the notification limitation without claiming delivery. |
| The gated phone receives permission later | Permit its unsent update alert while incompatibility remains. Preserve duplicate suppression and revalidate the gate. |
| The user opens an old update notification after recovery or an account change | Revalidate the current state. Do not restore an old scope or block a compatible account from stale notification data. |
| A compatible update restores access | Recreate the scope and permit, respect recording consent and permissions, and clear the owned update alert. |
| An incompatible record arrives before the shared required-major metadata | Detect its unsupported contract before interpretation and enter the update gate. Do not publish a partial compatible-looking result. |
| A shared major upgrade is attempted while offline or its server confirmation fails | Do not activate incompatible behavior. Preserve the highest known major and verify the outcome before retrying activation. |
| An eligible beta activates a major before a compatible App Store release exists | Apply the ordinary shared-upgrade rules. Require beta use across devices and update incompatible phones through the existing gate. |
| A phone returns from Beta to an App Store build that cannot honor the required major | Keep access gated. Require a compatible beta or App Store build without lowering the required major. |
| An earlier-version choice arrives after a major upgrade | Apply the defined version-admission rules. Preserve safely interpretable meaning, or retain the record and require review with affected history unresolved. |
| An idle updated device only produces unused pings | Do not automatically advance the required major from that activity. |
| A stationary device contributes useful recent history | Permit it to qualify for an automatic major upgrade without movement. |
| A replacement phone has no recent contribution | Offer an explicit shared-data major upgrade and retain its new recording identity. |
| Compatible minor or patch versions assess identical inputs | Permit different automatic history, totals, and issues. Preserve the shared decision contract without a compatibility gate. |
| Identical full policy versions assess identical evidence, decisions, and query context | Produce identical history regardless of input or sync order. |
| A device installs a compatible policy update | Invalidate affected cached results and reassess automatic history. Preserve raw observations and user choices without a shared-data upgrade. |
| A new control has a meaning that older clients cannot honor | Require a major upgrade before activation and gate clients that cannot honor the new contract. |
| A new installation has an empty store before account data arrives | Keep account verification unknown. Do not initialize or advance the required major from local emptiness. |
| Shared legacy data exists without compatibility metadata | Treat the account as existing. Establish its applicable major through the legacy bootstrap path. |
| Account verification fails or remains incomplete | Retain unknown status and the last observed required major. Expose retry without claiming that an app update is necessary. |
| Shared account verification establishes a new account | Initialize the current supported major through guarded creation. |
| Two devices attempt first setup concurrently | Adopt the established shared account state. Do not overwrite it or bypass major-upgrade rules. |
| Two offline devices choose different sources for the same period | Preserve both decisions and request review of the overlap. |
| A decision arrives before one of its predecessors | Preserve incomplete knowledge instead of claiming a complete revision prefix. |

These scenarios define acceptance criteria. They are not claims of current test coverage.

## Formal verification

Protocol activation requires PlusCal specifications checked with TLC.
The models follow the existing [specification workflow](Specifications/README.md) and live under `Where/Specifications/`.
They check narrow properties within explicit bounds and assumptions.
They do not establish an unbounded mathematical proof or prove that the Swift implementation matches the model.
The original design PR adds these requirements only.
The first implementation adds [MultiDeviceDecisions](Specifications/MultiDeviceDecisions/README.md), with one passing model and four negative or reachability controls.
Its current configuration checks 256 distinct states across two replicas and four fixed operations.
All five cases pass their expected-result checks. The other model families remain required before activation.
The compatibility slice also adds the [write-lifetime model](Specifications/CompatibilityWrites/README.md).
Its passing configuration checks 75 distinct states. Three negative controls and one reachability control pass their expected-result checks.
This model covers permit revocation and local saves only. It does not validate shared verification, activation, or output publication.
The [verification model](Specifications/CompatibilityVerification/README.md) covers shared and local initialization, stale responses, and record-first delivery.
The [activation model](Specifications/CompatibilityActivation/README.md) covers durable grant invalidation and uncertain server responses.
Their twelve and four configurations respectively meet all expected-result checks. Output withdrawal still requires integration coverage.

| Model family | Required properties | Owning implementation slices |
| --- | --- | --- |
| Decision merging | Replicas with the same complete decision set and major contract converge regardless of delivery order, duplicates, or compatible minor and patch differences. Incompatible concurrent choices survive until explicitly resolved. Missing revisions never count as observed. Recovery never assigns an existing operation identity to a new operation. Replacements affect only their specified periods. | 1 establishes the model. 4 refines it against durable decisions and counter recovery. |
| History selection | Equal evidence, decisions, full policy versions, and query context produce equal history. Compatible policies can differ in automatic results while preserving shared decision semantics. Late uploads respect explicit choices and historical ignore intervals. Resume, expiry, and undo have distinct effects. Selection preserves raw observations and never fills an explicitly selected device's gaps from another device. | 4 models ignore intervals. 5 completes the model against shared history selection. |
| Compatibility and scope retirement | The required major never decreases. Minor and patch differences alone never revoke access. Stale verification cannot restore revoked access. Suspended work cannot commit through a revoked permit. Recovery uses a new scope and permit. Offline behavior follows the selected activation policy. | 3 defines and checks the compatibility protocol. |

History-selection cases require explicit source choices to take precedence over ignore intervals, including after expiry and under reordered delivery.
Return to automatic reapplies the historical ignore filter by observation time.
An ignore interval and an overlapping source choice do not create a conflict from that overlap alone.
Late eligible observations from the selected device can change history without changing the source decision.
Other devices remain excluded within that decision's scope, including gaps before and after the late import.
Swift tests cover refreshed totals, unchanged choices, and normal issue routing after new selected-device evidence.

History-selection cases keep permanent removal cutoffs effective under explicit source choices, regardless of delivery order.
Observations before the cutoff remain eligible. Observations at or after it remain excluded, including late uploads.
Removal preserves the source choice and its gaps until the user saves a replacement choice or returns that portion to automatic.

Swift tests cover review routing, selection of another device, and return to automatic without changing earlier portions.
Swift tests also verify that corrections cannot bypass exclusions.
They check source choices against the contracts for manual entries, overlays, and evidence-derived assertions.

The history-selection model excludes disputed contributions while preserving resolved presence from other periods on the same day.
Swift tests verify incomplete status, distinct affected-day counts, and contribution consistency across consumers.
Export tests require resolved history for the exported scope and one snapshot for eligibility and content.
They cover failed assessment, unaffected scopes, disabled reminders, and lossless backups with unresolved decisions.

The history-selection model retains resolved recording days and their context under sync, import, and viewer time-zone changes.
It compares competing observations by absolute time even when their recording-day labels differ.
Matching UTC dates alone never establish overlap.
Overlapping region agreement with conflicting day labels requires source selection for both region and day.
Unresolved recording-day conflicts preserve both raw assignments, exclude disputed contributions, and mark each candidate day incomplete.
Whole-day coverage and overlap with fixed time ranges must follow the selected device's recorded calendar context.
The model includes disjoint whole-day coverage after a date repeats and preserves intervening periods with other date labels.
Whole-day saves require unambiguous calendar coverage. GPS gaps alone do not invalidate coverage established by recorded calendar context.
Swift tests cover delayed callbacks, unresolved day assignments, daylight-saving changes, date-line travel, and day/year query boundaries.

The decision-merging model includes identity preservation after recovery and identity rotation after reset or rejoin.
It checks that recovery or backup replay never assigns an existing operation identity to a new decision.
Reviewed-write cases bind the new operation to the reviewed causal context and reject stale proposals at the guarded commit boundary.
The model covers relevant imports before validation, during the write, and after commit.
It also covers unrelated imports and data-generation retirement.
Local transaction guarantees do not imply a server-accepted decision or knowledge of an unseen major upgrade.

Reviewed-write cases preserve unaffected decisions and periods when issues split or merge before save.
Swift tests cover queue scope retention, changed identifiers, splits, merges, new device evidence, duplicate scopes, and failed reassessment.
They verify that unrelated work remains accessible and that completion requires successful assessment of the original concern.

The models allow delayed earlier-version decisions after major activation.
Unsafe interpretation cannot produce an effective choice or erase the retained decision.

The history-selection model keeps geographic agreement independent of reporting groups.
Grouping distinct regions under Other cannot turn conflicting tracks into agreement.
Unresolved geography alone establishes neither agreement nor a device conflict.
The model assumes that every admitted automatic GPS observation has a recording-device identity.
Conversion and Swift admission tests must validate this assumption before selection.

The compatibility model distinguishes cloud-backed datasets from local-only datasets.
Local-only initialization and major activation use guarded local transactions without account verification or server confirmation.
Local access never grants a shared-account permit or bypasses record admission.
For cloud-backed datasets, the model includes unknown, verified-existing, and verified-new account states.
Only verified-new state can authorize account initialization.
Unknown state cannot authorize initialization or a major upgrade.
Concurrent initialization cannot overwrite established account state or bypass upgrade rules.
The model also covers legacy-data discovery, verification failures, and delayed initial imports.

Cached offline access survives elapsed time and failed refreshes only for the same verified account and store.
The model rejects cached access after an identity change or known incompatibility and blocks new capture through the retired scope.
Recovery creates a new scope and cannot reuse a revoked permit or lower the known required major.
Shared major activation requires the guarded server confirmation, while metadata and incompatible records remain independently deliverable.
Swift tests cover durable retry-data preservation, notification denial and failure, repeat suppression, stale notification routing, and recovery cleanup.
They also cover offline local-only startup and upgrades, unsupported backup admission, and shared-output gating through local adapters.
Beta and App Store transition scenarios retain the same required-major gate without a separate channel-verification protocol.
Notification delivery never supplies a compatibility permit or proof that recording resumed.

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
GPS quality, movement thresholds, calendar arithmetic, and restore or transfer behavior require scenario and property tests.
Use deterministic platform fixtures for restore, transfer, and shared-account delivery. Record their assumptions and coverage limits.
Model checking cannot establish which phone actually accompanied the user.

## What main already provides

The new stack starts from the existing implementation.
It does not require a wholesale import of the previous stack.

| Existing owner | Reuse boundary |
| --- | --- |
| [RecordingDeviceID](WhereCore/Sources/Devices/RecordingDeviceID.swift) and [LocationSample](WhereCore/Sources/Location/LocationSample.swift) | Installation identity and automatic-sample provenance already exist. The current sample shape still permits missing GPS attribution. |
| [DeviceRecordingController](WhereCore/Sources/Devices/DeviceRecordingController.swift) | Local consent and device lifecycle already operate without exclusive ownership. |
| [LocationIngestor](WhereCore/Sources/Location/LocationIngestor.swift) and [LocationOutbox](WhereCore/Sources/Location/LocationOutbox.swift) | Capture stamps provenance and retains accepted writes across persistence failures. |
| [LocationHistoryReader](WhereCore/Sources/Devices/LocationHistoryReader.swift) | The shared read boundary already applies device removals and region corrections. |
| [LocationHistoryReaderTests](WhereCore/Tests/LocationHistoryReaderTests.swift) | Existing guards preserve raw observations while applying corrections and removal cutoffs. |
| [DayAggregator](WhereCore/Sources/Days/DayAggregator.swift) | Current GPS bucketing derives days from timestamps and the query calendar. Recorded-day grouping requires a replacement across consumers and day/year queries. |
| [YearReport](WhereCore/Sources/Reporting/YearReport.swift) and [YearReportDetails](WhereCore/Sources/Reporting/YearReportDetails.swift) | Reports currently carry day counts and related projections without unresolved selection state. Add unresolved periods and completeness to the shared consumer contract. |
| [ElsewhereResolver](WhereCore/Sources/Reporting/ElsewhereResolver.swift) and its [regression tests](WhereCore/Tests/ElsewhereResolverTests.swift) | Existing catalog lookup expands ordinary Other observations for presentation. Reuse that lookup in shared geographic assessment before selection and report grouping. |
| [Backup upgrader](Tools/upgrade-backup.rb) and its [regression tests](Tools/Tests/upgrade_backup_test.rb) | Existing offline conversion preserves archives but currently adds nil device attribution when absent. Required attribution needs a new conversion step and guards. |
| [HomeRegionRecord](WhereCore/Sources/Forecasting/HomeRegionRecord.swift) | The forecast home identifies a region. It does not supply a precise home or temporary base. |
| [ReminderReconciler](WhereCore/Sources/Reminders/ReminderReconciler.swift) and [DataIssueAlertReconciler](WhereCore/Sources/Reminders/DataIssueAlertReconciler.swift) | Missing-history and issue reminders currently use separate notifications. Issue counts currently use the current year. The replacement must include historical years. |
| [WherePreferences](WhereCore/Sources/Preferences/WherePreferences.swift) | Reminder enablement and schedules already use local preferences. When setup exposes these settings, preserve enabled defaults and independent recording consent. |
| [LoggingReminderScheduler](WhereCore/Sources/Reminders/LoggingReminderScheduler.swift) | The injected notification-center adapter supports local requests and owned cleanup. Reuse it for the update alert without relying on the retired history scope. |
| [RecordingDeviceCheckIn](WhereCore/Sources/Devices/RecordingDeviceCheckIn.swift) and [DeviceRecordingController](WhereCore/Sources/Devices/DeviceRecordingController.swift) | Device activity and recording status are advisory. They provide no guarantee of periodic delivery or complete observation uploads. |
| [StoreRemoteChangeSource](WhereCore/Sources/Persistence/StoreRemoteChangeSource.swift) | Imported history refreshes readers. It does not establish knowledge of all devices. |

The current [recording context](WhereUI/Sources/Launch/InstallationRecordingContextStore.swift) composes Keychain identity with a file excluded from backups.
The file retains consent, import recovery, and terminal onboarding-import authority.
An ordinary update adopts the previous excluded sidecar identity once, then binds the sidecar to Keychain.
A missing Keychain item never adopts an already-bound sidecar identity.
Reset and rejoin commit identity rotation before sidecar cleanup; retries retain the committed replacement.
The [recording-context regression tests](WhereUI/Tests/InstallationRecordingContextStoreTests.swift) cover these local recovery paths.
The current reader has no device-selection policy or unresolved-conflict result.
Its attribution uses the tracked region set. Full-catalog assessment remains an integration change.
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
Model recording-day assignments with their observation-time zone context, including an explicit unresolved state.
Define whole-day coverage from the selected device's recorded context and compare conflicting evidence by absolute time.
Support disjoint coverage when a logical date repeats, without including intervening periods assigned to another day.
Distinguish missing GPS from missing calendar context that prevents a whole-day save.
Establish overlap from full timestamps and bounded track coverage, independently of UTC calendar-date equality.
Require recording-device identity in the automatic GPS inputs to the new resolver.
Model regular homes and temporary bases as optional evidence with historical validity.
Use the required scenarios as executable fixtures.
Preserve reporting agreement for matching regions and recording days, and retain separate device trajectories.
Resolve recording-day conflicts through strong source evidence or the existing review flow.
Assess agreement with full-catalog region identities, independently of primary-region reporting groups.
Represent unresolved geography without inferring agreement or conflict from equal fallback values.
Define causal replacement, concurrent overlap, reversal, and agreement without production writes.
Give the resolver a full policy version and fixtures for deterministic results from identical inputs.
Add the initial decision-merging specification and its TLC control cases.
Exercise reordered, duplicated, and incomplete inputs. This slice does not change production filtering.

**Implemented foundation:** the [initial policy](#initial-assessment-policy), [causal resolver](#sync-and-concurrent-decisions), and bounded decision model have executable fixtures.
The module [README](WhereCore/README.md#multi-device-assessment-foundation) describes the pure API boundary.
Observation-time context acquisition remains an early investigation for slice 4.

### 2. Device identity and setup

Implement device-local Keychain identity with explicit unavailable and recovery states.
Implement the [identity and consent lifecycle](#device-identity-and-setup), including deliberate rotation and renewed consent after reset, rejoin, reinstall, or system restore.
Add the additional-device and replacement-device setup choices.
Expose local reminder settings with enabled defaults, independently of recording consent.
Preserve local identity and consent during in-app backup imports, including replace.
Keep removed identities retired and distinguish absent Keychain items from inaccessible items.
Cover updates, relaunches, backup imports, same-phone recovery, new-phone transfer, reset, rejoin, and Keychain failures.
Validate restore and transfer through the automated lifecycle fixture before activation.

**Implemented local behavior:** [Keychain storage](WhereCore/Sources/Devices/KeychainRecordingIdentityStore.swift) and the [recovery policy](WhereCore/Sources/Devices/RecordingIdentityRecoveryPolicy.swift) distinguish absence from failure.
Setup offers replacement candidates without suppressing this phone's recording default.
Removal requires a separate choice and confirmation. Reminder categories retain their local enabled defaults and existing schedules.
Renewed consent triggers import recovery before recording. Pending imports retain the original receipt owner after identity changes.
A surviving removed identity reaches the existing explicit rejoin flow.
Consent confirmation and setup completion have separate durable states.
An interrupted setup requires confirmation again, even when restored preferences report completed onboarding.
The user can reselect an unfinished replacement removal; the app does not replay that destructive choice automatically.

**Automated lifecycle gate:** use two isolated installations and a scripted shared account.
Keep Keychain, backup-excluded sidecars, backed-up preferences, raw history, and server state as separate fixture resources.
Drive update, relaunch, merge import, replace import, reinstall, same-phone restore, new-phone restore, and direct transfer.
Model surviving, absent, inaccessible, and removed Keychain identities independently of restored preferences.
Assert identity and consent against the [lifecycle table](#device-identity-and-setup).
For reset and rejoin, assert a new identity and unchanged historical provenance.
Hold persistence and sync at their suspension boundaries to exercise crashes, retries, account changes, and reordered delivery.
Use production recovery, store, import, and conditional-update code through injected platform adapters.
The fixture must fail if identity migrates, consent restores, an operation ID repeats, or an obsolete scope writes.
Record platform assumptions separately from tested app behavior. Manual device checks are optional diagnostics, not an implementation gate.

**Implemented lifecycle fixture:** [isolated installations](WhereUI/Tests/Support/INSTALLATION_FIXTURE.md) use production file adapters, temporary SQLite stores, launch, imports, and conditional shared control.
Cases cover relaunch, reinstall, same-phone restore, new-phone restore and transfer, merge and replace imports, reset, rejoin, Keychain failure, and account changes.
Restored preferences cannot bypass renewed consent. Actual backup-exclusion attributes determine which files transfer.
Held conditional creates force the concurrent-initialization race. Reordered delivery tests retain attribution and reject unsupported records before their control metadata arrives.
Slice 4 extends this fixture with durable decision identities and reviewed writes.

### 3. Compatibility gate

**Implemented guard foundation:** scoped reads and transactions use an irrevocable permit.
The physical SwiftData save and revocation share one mutex.
A held-transaction regression verifies that retirement discards staged changes before save.
The [write-lifetime model](Specifications/CompatibilityWrites/README.md) checks this boundary and recovery with a fresh permit.
Production scope creation now receives admitted services through the retained dataset owner.
The conditional-update fixture exercises the shared-account protocol through its production adapter boundary.

**Implemented protocol foundation:** account verification, conditional creation and activation, account-bound cache persistence, and record-header admission have executable fixtures.
The transport fixture runs the production algorithm with a controlled conditional database.
SwiftData fixtures exercise unsupported and supported-major imports before a suspended physical save.
Shared observations stay in the account-bound local cache, so an old account's queued mirrored write cannot alter another account's control state.
Lazy store preparation verifies and initializes shared control state before creating the local CloudKit mirror.
Existing local file presence prevents accidental new-account activation. Actual headers must pass admission after the single shared open.
The production scope and output integrations below remain required before activation.

**Implemented retirement primitives:** output wrappers drain submitted system calls before withdrawing history notifications and widget output.
The [output model](Specifications/CompatibilityOutputs/README.md) checks this ordering and replacement publication.
Terminal recording retirement preserves accepted retry data, joins delayed physical starts, and rejects stale cleanup or resume calls.
Fresh scopes replay retained observations with their original device provenance.
Production launch and foreground/background refresh now use these primitives.
The compatibility gate precedes interrupted-import recovery for existing installations.
A new installation requests admission only after choosing discovery or setup of its real history.
Onboarding retains its draft through blocked checks. A retired scope cannot complete a pending setup or repeat an already committed import.
App Intents reject retired handoffs and validate history results, including their cached widget path.
Cold rejection stops and discards the prepared location source, even before services exist.
Shared-item drafts now remain outside history until an admitted app session imports them.
Atomic delivery receipts make retries safe after commit, deletion, Reset, or Replace.
The automated installation fixture also exercises these paths across process and file replacement.
Independent update alerts remain part of the review and activation slice below.

Selectively reuse compatibility guards, scope retirement, and stale-output withdrawal from the previous stack.
Remove ownership dependencies from these components.
Implement `major.minor.patch` semantics and the monotonic required major.
Distinguish cloud-backed datasets from local-only datasets independently of process adapters and network availability.
Implement guarded local initialization and major activation without account verification for local-only datasets.
Preserve record admission and compatibility gating in both paths.
Implement unknown, verified-existing, and verified-new account states from shared-account verification.
Define the evidence that establishes account newness and the legacy-data bootstrap path.
Guard account initialization against concurrent setup and preserve previously observed requirements after verification failures.
Apply recent-contributor eligibility and the explicit upgrade action to major upgrades only.
Keep compatible minor and patch differences outside the incompatible-data gate.
Reuse local permits, scope retirement, and normal mirroring without a separate server-confirmed decision-publication path.
Implement cached offline access without time-based expiry for a verified compatible account and store.
Revoke access on identity changes or known incompatibility, including incompatible records received before their metadata.
Pause capture at the known-incompatible gate while preserving consent and accepted durable retry data.
Keep update notification scheduling and routing available after scope retirement.
The share extension saves attachments and metadata as pending drafts without opening the history store.
The next verified app session imports them through its guarded services.
Retain each draft until its import is durable. Repeated delivery or a crash after commit must not duplicate evidence.
Preserve pending drafts while compatibility blocks the app.
Define and verify shared major activation, version admission, and initial rollout before incompatible data writes.
Adapt the compatibility and scope-retirement models to that protocol and its actual atomicity boundaries.
Cover empty local stores, delayed imports, legacy accounts, concurrent setup, stale responses, old backups, and failed verification.
Cover offline local-only startup and upgrades, unsupported imports, and cloud-backed output through local adapters.
Cover beta upgrades and return to App Store builds under the existing compatibility gate.
Exercise foreground and background consumers.

### 4. Durable choices, device controls, and places

**Implemented control values and store boundary:** source choices, ignore edits, place edits, and calendar-context edits share the pure causal interval resolver.
All controls retain immutable identities and predecessor sets through serialization.
Resume preserves elapsed ignored history. Place and calendar edits retain historical validity and expose conflicting or incomplete context.
Recording-day values retain established UTC offsets, so later time-zone database changes cannot reinterpret their logical dates.
Versioned envelopes retain affected scope outside opaque payloads. Unknown interpretation remains available for review with its original bytes.
The store validates identity, causal family, and the complete received graph before admitting controls.
Canonical predecessor order preserves retry bytes across restoration. Reset and Replace erase outgoing payloads without lowering known compatibility requirements.
Recording-day assignments now persist with raw samples. Major-one boundaries reject missing attribution or assignments without supplying historical defaults.
Major-one observations use atomic version envelopes, including their required major and complete payload.
Record-first delivery therefore exposes the requirement before any incompatible observation can reach a foundation reader.
Merge rejects conflicting raw payloads that reuse an observation identity.
Backup format 9 retains controls, affected scopes, ongoing home validity, and original payload bytes across Merge and Replace.
The offline converter accepts reusable sample mappings for historical devices and calendar context, including explicitly unresolved context.
A shared Ruby/Swift fixture validates the converted wire shape through the production decoder.
Reviewed source choices now retain their operation identity and observed predecessors across guarded retries.
Changed relevant inputs return a refreshed review. Unrelated imports can retry the same proposal without another confirmation.
Whole-day proposals require complete calendar context and retain separate repeated-date intervals.
Ignore, place, and calendar edits now use the same guarded transaction as source choices.
Shortening an ignore restores its old tail within the same immutable operation and retains the new end day and zone.
If a concurrent edit extends that interval, the refreshed preview includes its tail and requires another Apply before saving.
Resume intents use the same refresh rule while retaining their original cutoff. Elapsed history and separate intervals remain outside that edit.
The coordinator now reads durable ignore history and previews exact ignore proposals through the shared control selector.
These values retain elapsed periods, gaps, causal uncertainty, source-choice precedence, removal cutoffs, and unknown controls for the controls UI.
The coordinator also reads historical place definitions by identity and previews the exact reviewed place edit.
Past definitions, removals, disjoint validity periods, and unresolved control scopes remain visible. These previews describe supporting places, not recorded presence or totals.
Regular homes now support explicit ongoing validity. Temporary bases require an end.
Changes and endings preserve earlier definitions. The shared causal resolver handles finite queries and ongoing place history without invented expiration dates.
Place proposals bind their complete validity and detect future definitions received before Apply. Their previews describe definitions rather than GPS contributions or totals.
The offline upgrader preserves finite place payloads and identities while converting their envelope scope. The place controls UI remains to be implemented before activation.
Calendar recovery resolves unknown assignments while preserving known recording days and UTC offsets.
A late conflicting observation rejects a pending calendar edit before save.
`RecordingCalendarRecovery` splits an explicitly confirmed historical zone at each offset transition, without filling unconfirmed gaps.
The edit coordinator reviews these segments together and saves them in one local transaction.
Each envelope retains its own remote-delivery scope. A partial delivery requires another review before a retry can finish the batch.
The admitted services expose these coordinators and await the existing reconciliation after save.
Capture-time context, shared history selection, and the controls UI below remain required. The foundation policy still blocks these writes.
Observation imports now use transaction-scoped envelope indexes and an indexed lookup for legacy sample identities.
Fresh compatibility and persistent-history checks remain adjacent to physical save; indexes do not replace those checks.
Scaling fixtures exercise large SQLite imports and retries. Late identity conflicts in erased generations remain inert.
The [reviewed-choice model](Specifications/ReviewedRecordingChoices/README.md) checks bounded retry identity and causal context.
It does not claim that a synchronous local history check excludes a CloudKit import or observes another device's unsent changes.
`RecordingControlSelection` now resolves source choices, historical ignores, and removals before automatic assessment.
Explicit choices bypass ignores. Removed selected devices leave exclusive gaps that require review.
Automatic eligibility retains unresolved ignore edits; unknown controls retain their affected scopes.
The [control-selection model](Specifications/RecordingControlSelection/README.md) covers bounded delivery order and historical expiry.
Shared consumer integration remains in slice 5.
The installation fixture now covers decision identity through restore, reinstall, transfer, and both archive-import strategies.
Concurrent edits from independent phones retain their identities until a reviewed replacement names both predecessors.
These fixtures exposed the distinction between an admitted account contract and its not-yet-delivered local metadata.
Source/control writes, GPS storage, and backup boundaries now use the admitted contract without mirroring account-only verification state.

Extend the value-based store and backup contracts with source choices, ignore intervals, regular homes, and dated temporary bases.
Persist observation timestamps, recording-day assignments, and their time-zone context without recalculation during sync or import.
Extend historical conversion for missing recording-day metadata with supported evidence or explicit mappings.
Define capture and recovery of observation-time context for delayed callbacks and unobserved device time-zone changes.
Require device attribution for automatic GPS in the new stored-data contract.
Bump the backup format and extend the offline upgrader with explicit historical source-device mappings.
Preserve existing identities and raw observation fields during conversion.
Cover repeat conversion across archives, missing mappings, and rejection of unattributed GPS at admission.
Validate converted archives through the production backup decoder and preserve local identity and consent during replace-import.
Complete historical data repair and compatibility protection before activating the required-attribution contract.
Implement causal context, durable reversal, and concurrent-choice behavior.
Persist authoring data-semantics versions and validate them before applying decisions.
Retain decisions that lack a safe interpretation and expose their affected history for review.
Bind reviewed writes to their evidence, decisions, period, policy, query context, causal context, and expected data generation.
Reassess and save inside the guarded transaction without adopting unreviewed causal predecessors.
Exercise relevant and unrelated imports before validation, during the write, and after commit.
Reject writes under retired generations or revoked compatibility permits.
Add compatibility fixtures for shared decision interpretation across supported minor and patch versions.
Refine the decision-merging model against persistence, dependency delivery, and counter recovery.
Add history-selection model cases for ignore intervals, resume, expiry, and undo.
Implement explicit-choice precedence over ignore intervals for existing and new choices, regardless of write or delivery order.
Cover return to automatic after ignore expiry and independent creation of overlapping ignore and source choices.
Implement the agreed precedence with per-sample corrections, manual overlays, and device removals.
Keep removal cutoffs effective under source choices without rewriting those choices or admitting another device into their gaps.
Cover reordered removals, late uploads, and resolutions limited to the affected portion.
Cover expiry, time-zone changes, late imports, partial delivery, counter recovery, and both backup import strategies.
Preserve the provenance of retained observations and decisions across account data operations.
Apply the identity lifecycle instead of preserving local identity through every operation.
Prevent backup import and recovery from reusing decision operation identities.

### 5. Shared history selection

**Pure integration boundary implemented:** `RecordingHistorySelection` combines source controls, eligibility, removals, and bounded assessment.
It preserves raw observations, returns selected contributions, and exposes unresolved periods with candidate logical dates.
Multiple-region corrections and explicit unknown or excluded presence remain distinct before reporting groups are applied.
Attributed contributions now carry a separate selected logical day. Aggregation preserves that day across viewing zones.
Logical date queries provide offset-complete search bounds before filtering selected contributions.
`LocationHistoryReader` now performs that join in one store snapshot, with bounded adjacent evidence.
One lazy historical catalog serves both selection and Elsewhere. Internal capture deduplication still reads raw observations.
Elsewhere preserves selected dates, specific GPS geography, explicit unknown presence, and non-GPS enrichment.
Report and map queries now use logical dates. Reports, Elsewhere, and issue inputs retain completeness and exclude disputed contributions.
`exportableYearReport` checks the exact returned snapshot. It does not implement a report file format or export screen.
The daily recap withholds counts while its year is unresolved or assessment fails.
Flight and boundary inference respect selection exclusions even when the excluded interval contains no observations.
Completed flights retain selected recording dates. Losing source eligibility ends live presentation without establishing arrival.
Correction reviews retain relevant selection context and logical dates; restoration previews use specific geography before reporting groups.
Previews read current primary regions and reassess competing devices when the proposed geographic correction can change automatic selection.
Widget and intent integration, review presentation, and the selection model remain in progress.
Production remains on the foundation contract.

Extend `LocationHistoryReader` with effective selections and explicit unresolved conflicts.
Group selected observations by resolved recording day consistently across consumers.
When overlapping devices disagree on the day, select region and recording day together.
Keep candidate days incomplete while that conflict remains unresolved, and exclude its disputed contribution.
Preserve observable uncertainty for unresolved day assignments.
Cover day/year queries whose observations fall outside the viewing zone's corresponding instant window.
Apply selection before region aggregation and preserve device boundaries through movement and flight inference.
Separate full-catalog geographic assessment from primary-region reporting groups.
Retain specific region identities and unresolved geography through history selection.
Make Elsewhere consume the shared selection and uncertainty before it counts named visits.
Preserve explicit assertions of unknown presence during catalog lookup.
Cover reports, Elsewhere, issue scans, widgets, reminders, exports, and relevant App Intents.
Exclude disputed contributions while retaining resolved presence on the same day.
Expose incomplete status and distinct affected recording days across consumers, independently of reminder preferences.
Gate history-report exports on resolution within the exported scope, using one snapshot for eligibility and content.
Preserve lossless backup export while conflicts remain.
Carry the full policy version through derived results and caches.
Invalidate affected caches and reassess automatic history after policy updates.
Exercise compatible policy differences while preserving raw observations and the shared meaning of user choices.
Exercise simultaneous untracked-region conflicts, catalog gaps, and primary-region changes without changing selection from reporting groups alone.
Exercise local writes, delayed sync, user overrides, reset, and device removal.
Include late eligible observations from an explicitly selected device without changing the source choice or admitting another device into gaps.
Preserve raw review, lossless backups, and manual assertions.
Complete the history-selection model and add Swift regressions for its important counterexamples.
Verify unresolved contributions, report completeness, and export gating before activation.

### 6. Review experience, reminders, and activation

Add the temporary-ignore row, place controls, and inspection of automatic-selection reasons.
Explain that ignore affects automatic selection while explicit period choices take precedence, without another confirmation step.
Support logical recording-day choices, fixed time ranges, return to automatic, and previews of affected region-days.
Require clarification before a whole-day save with ambiguous calendar coverage, and retain the existing fixed time-range option.
When users resolve a recording-day conflict through source selection, show both candidate dates.
Route choices affected by device removal into review, with actions to select another device or return that portion to automatic.
Show incomplete totals and guide affected history-report exports into review before producing the report.
Add the local update alert, duplicate suppression, permission fallback, and current-state routing to the appropriate update destination.
Explain beta use across devices and the compatibility requirement for return to the App Store build during setup and updates.
Handle stale save proposals with a refreshed review before another confirmation.
Combine evening reminders and add notification routing into the bounded resolution flow.
Retain original review scopes independently of derived issue identifiers and reassess them through splits and merges.
Deduplicate overlapping work without expanding choices across gaps or unreviewed periods.
Require an updated preview for an explicit scope expansion and preserve pending work after failed reassessment.
Schedule independently on each device using local preferences, system notification permission, and available issue state.
Cover reminders on both phones, disabling one phone's reminders, and reminders with recording off.
Include device status issues for unavailable expected data in recent selected periods under the local issue-alert preference.
Show timestamped evidence and actions to check the source device, review the period, or change its choice.
Validate the policy for device status issues before activation.
Cover quiet devices, receiver sync failures, and independently arriving check-ins and observations.
When the user opens or skips a device status issue, keep source choices effective and unresolved work accessible.
Discover unresolved issues across all years containing history, independently of the current or selected year.
Use that historical scope for the main issue list and enabled reminder counts.
Carry each referenced issue's year, period, and query context through notification refresh and review lookup.
Cover year rollover, older-year notifications, and late imports that create historical issues.
Keep remaining work accessible through the issues bar button.
Use representative phone journeys and concurrent-edit scenarios in previews, snapshots, and interaction tests.
Require passing TLC cases and reviewed source correspondence before activation, as specified under [Formal verification](#formal-verification).
Activate selection after compatibility, durable decisions, shared consumers, and review surfaces satisfy the acceptance criteria.

## Decisions to resolve by implementation slice

Each open decision has an owning slice, a deadline, and required evidence.
The product decisions are recorded in the contract sections above.
Technical investigations can proceed early without activating production behavior.
The remaining technical decisions belong in their owning implementation PRs.

If an implementation result requires different user-visible behavior, discuss that change before adopting it.
After a decision is resolved, add its outcome to the relevant contract section.
Remove the resolved row from this section.
Record the supporting evidence in the owning PR. The evidence listed below is required work, not current test coverage.

### Investigate early

These investigations establish whether the proposed contracts work at the platform and persistence boundaries.
Their results must precede the dependent decisions listed here.

| Decision | Owning slice | Resolve before | Required evidence |
| --- | --- | --- | --- |
| Acquisition and recovery of observation-time zone context, including delayed callbacks and historical conversion | 4: persistence, with early investigation during 1 | Finalizing capture and persisted observation shapes in 4 | Platform experiments for delayed callbacks, time-zone changes, and relaunch. Conversion fixtures and a recovery path for unresolved assignments. Measure missing-context frequency on representative phone journeys. |
| Shared-account verification evidence and guarded initialization, including legacy-data bootstrap | 3: compatibility | Finalizing shared compatibility persistence in 3 | Concrete shared evidence and a deterministic fixture of the guarded operation through the production adapter boundary. Compatibility-model cases for concurrent setup, legacy data, and failed verification. |
| Guarded server confirmation for shared major activation, record-level version admission, and rollout | 3: compatibility | Finalizing incompatible record formats and writes in 4 | An automated fixture against the production store boundaries and passing compatibility-model cases for both delivery orders. A rollout procedure for pre-foundation clients. |

### Resolve in the owning implementation PR

| Decision | Owning slice | Resolve before | Required evidence |
| --- | --- | --- | --- |
| Device status eligibility, evidence requirements, freshness thresholds, and recovery conditions | 6: reminders | Activating device status issues or their notifications | Scenarios for quiet devices, receiver sync failures, delayed check-ins, recent selected periods, and recovery without complete observation delivery. |
| Meaningful-contribution criteria within the agreed 15-day window | 3: compatibility | Implementing automatic shared major upgrades | Fixtures for useful stationary history, redundant or excluded observations, late uploads, and explicit source choices. |
| Persistence and recovery for the agreed identity lifecycle and stored decisions | 2: identity, with durable decisions in 4 | Persisting the new state in each owning slice. Automated lifecycle validation precedes activation. | Both backup import strategies, reset, removal, rejoin, and counter recovery. Same-phone and new-phone restore or transfer fixtures with separate Keychain and backup resources. |

Thresholds require named units and scenario tests before they affect history.
The automatic policy produces the same result for identical evidence, decisions, full policy versions, and query context, regardless of input or sync order.
The first executable slice establishes that policy without changing capture or report behavior.
Activation follows durable choices, consistent consumer integration, compatibility protection, and a usable review path.

### Deferred discussion: time zone for fresh location fixes

**Open, deferred by the user on 2026-11-04. Resolve before activating capture under the new recording-day contract.**

Core Location supplies an observation timestamp, but no historical device time zone.
[`CLLocation.timestamp`](https://developer.apple.com/documentation/corelocation/cllocation/timestamp) records when the location was determined.
[`CLVisit`](https://developer.apple.com/documentation/corelocation/clvisit) supplies approximate arrival and departure times, which can precede delivery.
The current device zone does not prove which zone applied to an earlier observation.
This also applies after relaunch or an unobserved zone change.

The strict rule leaves an assignment unresolved unless saved context or user confirmation establishes it.
That protects historical dates, but could require review for many passive observations.
Representative journeys have not yet established how often this occurs.

The proposed alternative permits the current device zone for fixes no more than 60 seconds old.
Older fixes still require saved context or user confirmation.
This reduces expected review work, but a zone change within those 60 seconds can assign the wrong logical day.
The threshold alone cannot prove historical context.

Neither alternative was selected. Do not implement the proposed freshness exception as an approved policy.
Continue independent persistence, selection, and review work. Preserve unresolved assignments and raw observations until this discussion resumes.
After a decision, update the capture contract and its regression fixtures, then remove this discussion section.
