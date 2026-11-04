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

### Saving a reviewed choice

A save retains the reviewed period, relevant evidence and decisions, causal context, full policy version, query context, and data generation.
Reassessment and the decision write occur inside the same guarded transaction.
The transaction checks the expected data generation, relevant read state, and current compatibility permit.
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
[Offline compatibility](#offline-compatibility) defines version admission and the remaining access rules before activation.

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
4. Validate the reviewed inputs inside the guarded decision-write transaction.
5. If they changed, reject the proposal and show the updated issue before the user commits a choice.

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
For a given full policy version, automatic periods use the combined available evidence regardless of upload order.

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
Their evidence and full policy version explain the result and permit reassessment after late sync or a policy change.
Derived results and caches carry that full version.
A policy update invalidates affected cached results and reassesses automatic history without rewriting raw observations or durable user choices.
User choices are durable decisions with explicit period boundaries.
They retain their authoring data-semantics version, immutable identity, and reviewed causal context.
They take precedence over automatic selection and remain reversible.

Device selection applies to automatic GPS evidence.
It does not override manual entries, authoritative day overlays, or evidence-derived assertions.
It composes with existing per-sample region corrections.
Legacy samples without a device identity remain available without an invented identity.

Every consumer uses the same effective history contract.
Reports, widgets, reminders, issue scans, exports, and relevant App Intents use the same policy version on a device.
They agree for identical evidence, decisions, and query context after local writes, remote imports, user choices, and policy updates.
Different compatible policy versions can produce different automatic history, totals, and issues across devices.
They preserve the same shared meaning of durable user choices and controls.
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
Reusing a recording identity does not permit reuse of an operation identity for a new decision.
The causal persistence design defines safe recovery before new decision writes resume.
Dates remain useful for display and diagnosis. Wall-clock ordering does not decide between incompatible concurrent user choices.

Raw observations merge by stable identity and retain provenance.
Automatic selection recomputes from the available evidence and full policy version instead of accepting a remotely chosen derived winner.
Shared observations and decisions converge across compatible clients after all relevant records arrive, regardless of duplicates or delivery order.
Equal automatic history additionally requires identical full policy versions and query context.
Sync status reports observable facts, such as the last successful operation and known pending changes.
It never promises that every device is fully current.

## Compatibility

Data-semantics versions use `major.minor.patch`, separate from the app version.
The full data-semantics version also identifies the resolver policy.
The account carries a monotonic required major version for the shared data and decision contract.
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

### Account verification and initialization

Account verification distinguishes three states:

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
The separate offline policy determines capture and read access while verification is unavailable.

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
Automatic major-upgrade eligibility requires a meaningful contribution to effective history within the preceding **15 days**.
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

### Offline compatibility

The first version uses guarded local saves and the existing automatic CloudKit mirroring path for shared choices.
Save confirms local durability. It does not confirm server acceptance or knowledge of every device's current state.
The UI reports observable sync activity without a separate per-choice approval workflow.
The first version adds no offline-draft store or server-confirmed decision-publication protocol.
Future versions can add stronger confirmation at the save boundary because review proposals remain separate values.

On observing an unsupported required major, the client rejects further shared edits and requires an app update.
It preserves previously saved observations and decisions.
The client does not continue editing with an older resolver under the unsupported major.
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

Offline access remains an activation prerequisite.
Define when cached verification permits capture, reads, and shared edits, including expiry and recovery after verification failure.
Define the synchronization point for major activation and handling of independently arriving metadata and records.
The rollout must establish compatibility-aware clients before activating data that older clients cannot safely interpret.
A sync-completion event alone cannot provide that guarantee.

## Required scenarios

| Evidence or action | Expected behavior |
| --- | --- |
| Both phones report different coordinates within the same region | No device conflict. Preserve both sets of observations. |
| One phone travels while another repeatedly reports from home | Select the moving phone where evidence is strong. Explain the selection. |
| Several phones remain at home while one accompanies the user | Assess evidence without a device-count vote. |
| The user changes phones during the day | Permit different selected devices in different periods. |
| The app updates or relaunches normally | Preserve the installation's identity and local recording consent. |
| The user imports a backup through merge or replace | Preserve local identity and consent. Retained historical records keep their original provenance. |
| The user explicitly resets the app | Create a new identity and request recording consent again. Apply the existing data-reset contract. |
| A removed device rejoins | Create a new identity and request consent again. Keep the previous identity removed. |
| The user reinstalls Where or restores the same phone | Reuse a surviving valid Keychain identity, or create one through setup if absent. Request recording consent again. |
| The identity's Keychain item is inaccessible | Show retry or unlock state. Do not treat the item as absent or create a replacement identity. |
| A system backup restores or transfers to another physical phone | Create a new identity and establish local consent. Keep historical records attributed to their original devices. |
| Recovery retains an identity but encounters older counter state | Prevent operation-identity reuse. Complete safe recovery before new decision writes resume. |
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
| Relevant evidence or decisions change after the review opens | Reject the stale proposal and show the refreshed issue without applying the choice. |
| The guarded write detects changed inputs or a retired data generation | Abort the effective decision write. Preserve the reviewed causal context and require a valid current review. |
| A known compatibility change revokes the write permit | Reject the write and follow the compatibility gate. |
| An unrelated import leaves the reviewed inputs unchanged | Permit the valid choice without another user review after transaction revalidation. |
| An incompatible decision arrives after the local commit | Preserve its causal relationship to the reviewed decision set. Retain concurrent choices for resolution instead of silently replacing them. |
| A permitted account scope saves a choice while offline | Commit the guarded local write and use normal mirroring. Do not claim server acceptance. |
| An older client observes an unsupported required major | Require an app update and reject further shared edits. Preserve previously saved observations and decisions. |
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
This design slice adds the requirements only. It contains no new models or model-checking results.

| Model family | Required properties | Owning implementation slices |
| --- | --- | --- |
| Decision merging | Replicas with the same complete decision set and major contract converge regardless of delivery order, duplicates, or compatible minor and patch differences. Incompatible concurrent choices survive until explicitly resolved. Missing revisions never count as observed. Recovery never assigns an existing operation identity to a new operation. Replacements affect only their specified periods. | 1 establishes the model. 4 refines it against durable decisions and counter recovery. |
| History selection | Equal evidence, decisions, full policy versions, and query context produce equal history. Compatible policies can differ in automatic results while preserving shared decision semantics. Late uploads respect explicit choices and historical ignore intervals. Resume, expiry, and undo have distinct effects. Selection preserves raw observations and never fills an explicitly selected device's gaps from another device. | 4 models ignore intervals. 5 completes the model against shared history selection. |
| Compatibility and scope retirement | The required major never decreases. Minor and patch differences alone never revoke access. Stale verification cannot restore revoked access. Suspended work cannot commit through a revoked permit. Recovery uses a new scope and permit. Offline behavior follows the selected activation policy. | 3 defines and checks the compatibility protocol. |

The decision-merging model includes identity preservation after recovery and identity rotation after reset or rejoin.
It checks that recovery or backup replay never assigns an existing operation identity to a new decision.
Reviewed-write cases bind the new operation to the reviewed causal context and reject stale proposals at the guarded commit boundary.
The model covers relevant imports before validation, during the write, and after commit.
It also covers unrelated imports and data-generation retirement.
Local transaction guarantees do not imply a server-accepted decision or knowledge of an unseen major upgrade.

The models allow delayed earlier-version decisions after major activation.
Unsafe interpretation cannot produce an effective choice or erase the retained decision.

The compatibility model includes unknown, verified-existing, and verified-new account states.
Only verified-new state can authorize account initialization.
Unknown state cannot authorize initialization or a major upgrade.
Concurrent initialization cannot overwrite established account state or bypass upgrade rules.
The model also covers legacy-data discovery, verification failures, and delayed initial imports.

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
Its reset and rejoin operations already create new identities and require recording confirmation again.
The [recording-context regression tests](WhereUI/Tests/InstallationRecordingContextStoreTests.swift) establish those existing behaviors.
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
Give the resolver a full policy version and fixtures for deterministic results from identical inputs.
Add the initial decision-merging specification and its TLC control cases.
Exercise reordered, duplicated, and incomplete inputs. This slice does not change production filtering.

### 2. Device identity and setup

Implement device-local Keychain identity with explicit unavailable and recovery states.
Implement the [identity and consent lifecycle](#device-identity-and-setup), including deliberate rotation and renewed consent after reset, rejoin, reinstall, or system restore.
Add the additional-device and replacement-device setup choices.
Preserve local identity and consent during in-app backup imports, including replace.
Keep removed identities retired and distinguish absent Keychain items from inaccessible items.
Cover updates, relaunches, backup imports, same-phone recovery, new-phone transfer, reset, rejoin, and Keychain failures.
Validate restore and transfer on physical devices before activation.

### 3. Compatibility gate

Selectively reuse compatibility guards, scope retirement, and stale-output withdrawal from the previous stack.
Remove ownership dependencies from these components.
Implement `major.minor.patch` semantics and the monotonic required major.
Implement unknown, verified-existing, and verified-new account states from shared-account verification.
Define the evidence that establishes account newness and the legacy-data bootstrap path.
Guard account initialization against concurrent setup and preserve previously observed requirements after verification failures.
Apply recent-contributor eligibility and the explicit upgrade action to major upgrades only.
Keep compatible minor and patch differences outside the incompatible-data gate.
Reuse local permits, scope retirement, and normal mirroring without a separate server-confirmed decision-publication path.
Define the offline policy and activation protocol before incompatible data writes.
Adapt the compatibility and scope-retirement models to that protocol and its actual atomicity boundaries.
Cover empty local stores, delayed imports, legacy accounts, concurrent setup, stale responses, old backups, and failed verification.
Exercise foreground and background consumers.

### 4. Durable choices, device controls, and places

Extend the value-based store and backup contracts with source choices, ignore intervals, regular homes, and dated temporary bases.
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
Define precedence with per-sample corrections, manual overlays, and device removals.
Cover expiry, time-zone changes, late imports, partial delivery, counter recovery, and both backup import strategies.
Preserve the provenance of retained observations and decisions across account data operations.
Apply the identity lifecycle instead of preserving local identity through every operation.
Prevent backup import and recovery from reusing decision operation identities.

### 5. Shared history selection

Extend `LocationHistoryReader` with effective selections and explicit unresolved conflicts.
Apply selection before region aggregation and preserve device boundaries through movement and flight inference.
Cover reports, issue scans, widgets, reminders, exports, and relevant App Intents.
Carry the full policy version through derived results and caches.
Invalidate affected caches and reassess automatic history after policy updates.
Exercise compatible policy differences while preserving raw observations and the shared meaning of user choices.
Exercise local writes, delayed sync, user overrides, reset, and device removal.
Preserve raw review, lossless backups, and manual assertions.
Complete the history-selection model and add Swift regressions for its important counterexamples.
Define unresolved-conflict presentation before changing totals.

### 6. Review experience, reminders, and activation

Add the temporary-ignore row, place controls, and inspection of automatic-selection reasons.
Support exclusive period choices, whole-day convenience, return to automatic, and previews of affected region-days.
Handle stale save proposals with a refreshed review before another confirmation.
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
- The shared-account verification evidence and guarded initialization protocol, including legacy-data bootstrap.
- Treatment of unresolved conflicts in totals, history exports, widgets, and reminders.
- Persistence and recovery for the agreed identity lifecycle and stored decisions across backup import, reset, and device removal.
- Offline compatibility policy, activation synchronization, and the required rollout sequence.

Thresholds require named units and scenario tests before they affect history.
The automatic policy produces the same result for identical evidence, decisions, full policy versions, and query context, regardless of input or sync order.
The first executable slice establishes that policy without changing capture or report behavior.
Activation follows durable choices, consistent consumer integration, compatibility protection, and a usable review path.

## Pending review discussion

This temporary section preserves unresolved points from the reviews of `2658e4d4` and `bf1456f0`.
The proposals in this section are not agreed decisions.
R5–R7 remain the prioritized review findings, followed by E1–E5.
D1 and D2 retain the broader open decisions. D2 tracks the remaining offline-access and activation rules.
After agreement, update the relevant contract, acceptance scenarios, and implementation steps.
Then remove the resolved entry from this section.
When no entries remain, remove this section.

### R5. P2 — Include historical years in issue reminders

The plan keeps older issues eligible, but the current reminder scans only the current year.
A December conflict can disappear from reminders in January if the new flow retains that scope.
See the [current issue-alert reconciler](WhereCore/Sources/Reminders/DataIssueAlertReconciler.swift).
Proposal: preserve historical year context in issue discovery, notification queues, and review lookup.
Add a year-boundary acceptance scenario.

### R6. P2 — Distinguish Other from geographic agreement

The region-agreement rule does not distinguish a named region from the `Other` fallback.
Current attribution maps coordinates outside the tracked set to `Other`.
Two phones in Nevada and Oregon can therefore agree on `Other` during the same period.
The [Elsewhere resolver](WhereCore/Sources/Reporting/ElsewhereResolver.swift) expands those observations into separate named visits and counts both.
Its [regression tests](WhereCore/Tests/ElsewhereResolverTests.swift) establish this expansion without changing the main report's `Other` total.

If selection treats equal `Other` values as sufficient agreement, Elsewhere can show incompatible tracks as confirmed visits.
Proposal: distinguish agreement about a known region from shared fallback attribution.
Define the conflict policy for untracked regions and coordinates outside the catalog.
Apply the resulting selection or uncertainty to Elsewhere before it counts named visits.
Add simultaneous untracked-region and tracked-set-change acceptance scenarios.

### R7. P2 — Define source selection for unattributed GPS

Legacy GPS observations have no recording-device identity, but the plan does not define their eligibility during source selection.
The [current removal filter](WhereCore/Sources/Devices/RecordingDeviceRemovalFilter.swift) preserves these observations.
Its [regression test](WhereCore/Tests/RecordingDeviceRemovalFilterTests.swift) explicitly requires unattributed GPS to remain visible.

Example: an older backup adds unattributed New York GPS inside a gap in an explicit Duo selection for a California trip.
Passing those observations through device selection adds unwanted presence inside an exclusive period.
Discarding all unattributed GPS instead removes legacy-only history from reports.

Proposal: define eligibility for unattributed GPS in automatic periods and explicit selections without assigning an invented device identity.
Preserve raw evidence and legacy-only history.
Specify how unattributed GPS overlaps a selected device's gaps.
Add mixed-provenance, legacy-only, and late-backup-import acceptance scenarios.

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

An offline older app cannot immediately learn that another device raised the required major.
The [v1 save policy](#offline-compatibility) uses local durability, ordinary mirroring, and forced updates for known unsupported majors.
It prioritizes implementation simplicity and permits renewed user review after an upgrade when a saved choice cannot be interpreted safely.
The remaining decisions concern when an account scope can operate offline and how major activation becomes safe.

Define when cached verification permits offline capture, reads, and shared edits.
Specify verification expiry, recovery after failed checks, and behavior after account changes.
Decide whether raw capture continues when verification is unavailable or a known major blocks shared edits.
Specify the activation and rollout protocol, including independent arrival of compatibility metadata and incompatible records.
The compatibility models must check that protocol under explicit delivery assumptions before activation.

Concrete case: an offline device saves a choice locally and dismisses the review.
Another device activates a newer required major before the first device receives that change.
The pending choice can reach shared storage after the upgrade.
The protocol must preserve that choice and apply its version-admission rules without assuming immediate knowledge of the upgrade.

A connection check followed by a local save does not order the write against a concurrent major upgrade.
The current [SwiftData store](WhereCore/Sources/Persistence/SwiftDataStore.swift) uses automatic CloudKit mirroring.
Apple documents separate local saves, exports, and imports in [TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer).
The design cannot assume that application code verifies compatibility before every pending export.
Keep the decision about offline raw capture separate from the decision about shared edits.
