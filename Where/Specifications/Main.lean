import WhereSpecifications

open WhereSpecifications
open WhereSpecifications.TransitionSystem

structure Specification where
  name : String
  run : IO Bool

def runPair [Repr Action] (current broken : SearchResult Action)
    (brokenProperty : String) : IO Bool := do
  let brokenOK ← reportCase "broken" (.violation brokenProperty) broken
  let currentOK ← reportCase "current" .pass current
  pure (brokenOK && currentOK)

def runTracking : IO Bool := do
  let broken ← reportCase "broken" (.violation "CorrectAtQuiescence")
    TrackingReconciliation.brokenResult
  let stale ← reportCase "stale-reachability" (.violation "StalePermissionNotObserved")
    TrackingReconciliation.staleResult
  let current ← reportCase "current" .pass
    (TrackingReconciliation.currentResult .enabledThenDisabled)
  let denied ← reportCase "current-denied" .pass
    (TrackingReconciliation.currentResult .denied)
  let repeated ← reportCase "current-repeated" .pass
    (TrackingReconciliation.currentResult .repeated)
  let reversed ← reportCase "current-reversed" .pass
    (TrackingReconciliation.currentResult .reversed)
  pure (broken && stale && current && denied && repeated && reversed)

def runRemoteDeviceRemoval : IO Bool := do
  let broken ← reportCase "broken" (.violation "RemovalDominatesAdvisoryState")
    RemoteDeviceRemoval.brokenResult
  let critical ← reportCase "critical-reachability" (.violation "CriticalScenarioNotReached")
    RemoteDeviceRemoval.criticalResult
  let reordered ← reportCase "reordered-cutoff-reachability"
    (.violation "EarlierCutoffNeverArrivesLate") RemoteDeviceRemoval.reorderedResult
  let current ← reportCase "current" .pass (RemoteDeviceRemoval.currentResult .single)
  let multiple ← reportCase "current-multiple" .pass (RemoteDeviceRemoval.currentResult .multiple)
  pure (broken && critical && reordered && current && multiple)

def specifications : List Specification := [
  ⟨"IngestorQuiesce", runPair IngestorQuiesce.currentResult
    IngestorQuiesce.brokenResult "NoPersistAfterQuiesceDone"⟩,
  ⟨"IntentServicesHandoff", runPair IntentServicesHandoff.currentResult
    IntentServicesHandoff.brokenResult "NoSelfCreate"⟩,
  ⟨"LaunchLifecycle", runPair LaunchLifecycle.currentResult
    LaunchLifecycle.brokenResult "MemoNoDoubleRun"⟩,
  ⟨"LogRouting", runPair LogRouting.currentResult
    LogRouting.brokenResult "ShadowedScopeNeverRoutes"⟩,
  ⟨"PostWriteReconcile", runPair PostWriteReconcile.currentResult
    PostWriteReconcile.brokenResult "BrokenNoEarlyPing"⟩,
  ⟨"ScopeExclusivity", runPair ScopeExclusivity.currentResult
    ScopeExclusivity.brokenResult "NoOverlappingRealContainers"⟩,
  ⟨"StorePerformSerialization", runPair StorePerformSerialization.currentResult
    StorePerformSerialization.brokenResult "AtMostOneOutermost"⟩,
  ⟨"TrackingReconciliation", runTracking⟩]
  ++ [⟨"RemoteDeviceRemoval", runRemoteDeviceRemoval⟩]

def main (arguments : List String) : IO UInt32 := do
  let selected := if arguments.isEmpty then specifications else
    arguments.filterMap fun name => specifications.find? (·.name = name)
  if selected.length != (if arguments.isEmpty then specifications.length else arguments.length) then
    IO.eprintln "error: executable received an unknown specification"
    return 2
  let mut success := true
  for specification in selected do
    IO.println s!"==> {specification.name}"
    success := (← specification.run) && success
  pure (if success then 0 else 1)
