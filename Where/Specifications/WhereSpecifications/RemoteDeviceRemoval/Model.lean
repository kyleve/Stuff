import WhereSpecifications.Protocol

namespace WhereSpecifications.RemoteDeviceRemoval
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Configuration where | single | multiple
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive AdvisoryKind where | profile | checkIn | metadata
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive TargetPhase where | idle | reading | revoking | clearing | retired
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Identity where | old | new
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive ReaderEventKind where | none | advisory | removal
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def cutoffs : Configuration → List Nat
  | .single => [1]
  | .multiple => [1, 2]
def times : Configuration → List Nat
  | .single => [0, 1, 2]
  | .multiple => [0, 1, 2, 3]
def advisoryKinds : List AdvisoryKind := [.profile, .checkIn, .metadata]

def addNat (domain : List Nat) (value : Nat) (current : List Nat) : List Nat :=
  value :: domain.filter fun candidate => candidate != value && current.contains candidate

def addAdvisory (value : AdvisoryKind) (current : List AdvisoryKind) : List AdvisoryKind :=
  advisoryKinds.filter fun candidate => candidate = value ∨ current.contains candidate

structure State where
  publishedRemovals : List Nat
  readerRemovals : List Nat
  targetRemovals : List Nat
  publishedAdvisories : List AdvisoryKind
  readerAdvisories : List AdvisoryKind
  readerSamples : List Nat
  readerLastOldEvent : ReaderEventKind
  readerFirstRemovalCutoff : Option Nat
  targetNotification : Bool
  targetPhase : TargetPhase
  oldRecording : Bool
  oldBacklogPresent : Bool
  activeIdentity : Identity
  newRecording : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive Action where
  | createRemoval (cutoff : Nat)
  | publishAdvisory (kind : AdvisoryKind)
  | deliverRemovalToReader (cutoff : Nat)
  | deliverRemovalToTarget (cutoff : Nat)
  | deliverAdvisoryToReader (kind : AdvisoryKind)
  | deliverSampleToReader (timestamp : Nat)
  | beginTargetObservation | readTargetSnapshot | revokeOldRecording
  | discardOldBacklog | rejoinWithNewIdentity | enableNewIdentity | done
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨[], [], [], [], [], [], .none, none, false, .idle,
  true, true, .old, false⟩

def step (_implementation : Implementation) (configuration : Configuration) :
    Action → State → Option State
  | .createRemoval cutoff, s =>
      if cutoff ∈ cutoffs configuration ∧ cutoff ∉ s.publishedRemovals then
        some { s with publishedRemovals := addNat (cutoffs configuration) cutoff s.publishedRemovals } else none
  | .publishAdvisory kind, s =>
      if advisoryKinds.contains kind && !s.publishedAdvisories.contains kind then
        some { s with publishedAdvisories := addAdvisory kind s.publishedAdvisories } else none
  | .deliverRemovalToReader cutoff, s =>
      if cutoff ∈ s.publishedRemovals ∧ cutoff ∉ s.readerRemovals then some { s with
        readerRemovals := addNat (cutoffs configuration) cutoff s.readerRemovals
        readerLastOldEvent := .removal
        readerFirstRemovalCutoff := match s.readerFirstRemovalCutoff with
          | some first => some first
          | none => some cutoff }
      else none
  | .deliverRemovalToTarget cutoff, s =>
      if cutoff ∈ s.publishedRemovals ∧ cutoff ∉ s.targetRemovals then some { s with
        targetRemovals := addNat (cutoffs configuration) cutoff s.targetRemovals
        targetNotification := if s.targetPhase = .retired then s.targetNotification else true }
      else none
  | .deliverAdvisoryToReader kind, s =>
      if s.publishedAdvisories.contains kind && !s.readerAdvisories.contains kind then some { s with
        readerAdvisories := addAdvisory kind s.readerAdvisories
        readerLastOldEvent := .advisory }
      else none
  | .deliverSampleToReader timestamp, s =>
      if timestamp ∈ times configuration ∧ timestamp ∉ s.readerSamples then
        some { s with readerSamples := addNat (times configuration) timestamp s.readerSamples } else none
  | .beginTargetObservation, s =>
      if s.targetPhase = .idle ∧ s.targetNotification then some { s with
        targetPhase := .reading
        targetNotification := false }
      else none
  | .readTargetSnapshot, s =>
      if s.targetPhase = .reading ∧ s.targetRemovals ≠ [] then
        some { s with targetPhase := .revoking } else none
  | .revokeOldRecording, s =>
      if s.targetPhase = .revoking then some { s with
        oldRecording := false
        targetPhase := .clearing }
      else none
  | .discardOldBacklog, s =>
      if s.targetPhase = .clearing then some { s with
        oldBacklogPresent := false
        targetPhase := .retired }
      else none
  | .rejoinWithNewIdentity, s =>
      if s.targetPhase = .retired ∧ s.activeIdentity = .old then some { s with
        activeIdentity := .new
        newRecording := false }
      else none
  | .enableNewIdentity, s =>
      if s.activeIdentity = .new ∧ s.newRecording = false then
        some { s with newRecording := true } else none
  | .done, s => if quiescentBool configuration s then some s else none
where
  quiescentBool (configuration : Configuration) (s : State) : Bool :=
    (cutoffs configuration).all (· ∈ s.publishedRemovals) &&
    (cutoffs configuration).all (· ∈ s.readerRemovals) &&
    (cutoffs configuration).all (· ∈ s.targetRemovals) &&
    advisoryKinds.all s.publishedAdvisories.contains &&
    advisoryKinds.all s.readerAdvisories.contains &&
    (times configuration).all (· ∈ s.readerSamples) &&
    s.targetPhase == .retired && s.activeIdentity == .new && s.newRecording

def system (implementation : Implementation) (configuration : Configuration) :
    TransitionSystem State Action := ⟨[initial], step implementation configuration⟩

def EffectiveReaderRemoved (implementation : Implementation) (s : State) : Prop :=
  match implementation with
  | .current => s.readerRemovals ≠ []
  | .broken => s.readerLastOldEvent = .removal
def RemovalDominatesAdvisoryState (implementation : Implementation) (s : State) : Prop :=
  s.readerRemovals ≠ [] → EffectiveReaderRemoved implementation s
def ReaderCutoff (s : State) : Nat := match s.readerRemovals with
  | [] => 0
  | first :: rest => rest.foldl Nat.min first
def VisibleOldSamples (implementation : Implementation) (s : State) : List Nat :=
  match implementation with
  | .current => if s.readerRemovals.isEmpty then s.readerSamples
    else s.readerSamples.filter (· < ReaderCutoff s)
  | .broken => if s.readerLastOldEvent = .removal then
    s.readerSamples.filter (· < ReaderCutoff s) else s.readerSamples
def HistoryHonorsEarliestCutoff (implementation : Implementation) (s : State) : Prop :=
  s.readerRemovals ≠ [] → ∀ timestamp ∈ VisibleOldSamples implementation s, timestamp < ReaderCutoff s
def RemovedIdentityNeverRestarts (s : State) : Prop :=
  s.targetPhase = .clearing ∨ s.targetPhase = .retired → s.oldRecording = false
def RejoinCannotReviveRemovedIdentity (s : State) : Prop :=
  s.activeIdentity = .new → s.targetPhase = .retired ∧ s.targetRemovals ≠ [] ∧
    s.oldRecording = false ∧ s.oldBacklogPresent = false
def DistinctIdentityRecording (s : State) : Prop :=
  s.newRecording = true → s.activeIdentity = .new ∧ s.oldRecording = false

def CurrentSafety (s : State) : Prop :=
  RemovalDominatesAdvisoryState .current s ∧ HistoryHonorsEarliestCutoff .current s ∧
  RemovedIdentityNeverRestarts s ∧ RejoinCannotReviveRemovedIdentity s ∧
  DistinctIdentityRecording s ∧
  (s.targetPhase ≠ .idle → s.targetRemovals ≠ []) ∧
  (s.targetNotification = true → s.targetRemovals ≠ []) ∧
  (s.targetPhase = .retired → s.oldBacklogPresent = false)

private theorem currentPreserved (configuration action before after)
    (safe : CurrentSafety before)
    (transition : (system .current configuration).step action before = some after) :
    CurrentSafety after := by
  cases configuration <;> cases action <;>
    simp [system, step, step.quiescentBool, cutoffs, times, advisoryKinds,
      addNat, addAdvisory] at transition <;>
    simp_all [CurrentSafety, RemovalDominatesAdvisoryState, EffectiveReaderRemoved,
      HistoryHonorsEarliestCutoff, VisibleOldSamples, ReaderCutoff,
      RemovedIdentityNeverRestarts, RejoinCannotReviveRemovedIdentity,
      DistinctIdentityRecording] <;> grind

theorem currentSafety (configuration state)
    (reachable : Reachable (system .current configuration) state) : CurrentSafety state := by
  apply reachable_invariant (system .current configuration) CurrentSafety ?_
    (currentPreserved configuration) state reachable
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, RemovalDominatesAdvisoryState, EffectiveReaderRemoved,
    HistoryHonorsEarliestCutoff, VisibleOldSamples, ReaderCutoff,
    RemovedIdentityNeverRestarts, RejoinCannotReviveRemovedIdentity,
    DistinctIdentityRecording, initial]

theorem currentRemovalDominatesAdvisoryState (configuration state)
    (h : Reachable (system .current configuration) state) :
    RemovalDominatesAdvisoryState .current state := (currentSafety configuration state h).1
theorem currentHistoryHonorsEarliestCutoff (configuration state)
    (h : Reachable (system .current configuration) state) :
    HistoryHonorsEarliestCutoff .current state := (currentSafety configuration state h).2.1
theorem currentRemovedIdentityNeverRestarts (configuration state)
    (h : Reachable (system .current configuration) state) :
    RemovedIdentityNeverRestarts state := (currentSafety configuration state h).2.2.1
theorem currentRejoinCannotReviveRemovedIdentity (configuration state)
    (h : Reachable (system .current configuration) state) :
    RejoinCannotReviveRemovedIdentity state := (currentSafety configuration state h).2.2.2.1
theorem currentDistinctIdentityRecording (configuration state)
    (h : Reachable (system .current configuration) state) :
    DistinctIdentityRecording state := (currentSafety configuration state h).2.2.2.2.1

def CriticalScenarioReached (s : State) : Prop := s.readerRemovals ≠ [] ∧
  s.readerLastOldEvent = .advisory ∧ s.readerSamples.any (· ≥ 1) = true ∧
  s.targetPhase = .retired ∧ s.activeIdentity = .new ∧ s.newRecording = true
def EarlierCutoffArrivedLate (s : State) : Prop :=
  s.readerFirstRemovalCutoff = some 2 ∧ s.readerRemovals.contains 1 = true ∧
    s.readerRemovals.contains 2 = true

def brokenTrace : List Action := [.createRemoval 1, .deliverRemovalToReader 1,
  .publishAdvisory .profile, .deliverAdvisoryToReader .profile]
theorem brokenTraceValid :
    (TransitionSystem.run (system .broken .single) initial brokenTrace).isSome := by decide
theorem brokenViolatesRemovalDominatesAdvisoryState :
    let s := (TransitionSystem.run (system .broken .single) initial brokenTrace).get!.getLast!
    s.readerRemovals ≠ [] ∧ s.readerLastOldEvent = .advisory := by decide

def criticalTrace : List Action := [.createRemoval 1, .deliverRemovalToReader 1,
  .publishAdvisory .profile, .deliverAdvisoryToReader .profile, .deliverSampleToReader 1,
  .deliverRemovalToTarget 1, .beginTargetObservation, .readTargetSnapshot,
  .revokeOldRecording, .discardOldBacklog, .rejoinWithNewIdentity, .enableNewIdentity]
theorem criticalTraceValid :
    (TransitionSystem.run (system .current .single) initial criticalTrace).isSome := by decide
theorem criticalTraceReachesControl :
    let s := (TransitionSystem.run (system .current .single) initial criticalTrace).get!.getLast!
    s.readerRemovals = [1] ∧ s.readerLastOldEvent = .advisory ∧ s.readerSamples = [1] ∧
      s.targetPhase = .retired ∧ s.activeIdentity = .new ∧ s.newRecording = true := by decide

def reorderedTrace : List Action := [.createRemoval 2, .deliverRemovalToReader 2,
  .createRemoval 1, .deliverRemovalToReader 1]
theorem reorderedTraceValid :
    (TransitionSystem.run (system .current .multiple) initial reorderedTrace).isSome := by decide
theorem reorderedTraceReachesControl :
    let s := (TransitionSystem.run (system .current .multiple) initial reorderedTrace).get!.getLast!
    s.readerFirstRemovalCutoff = some 2 ∧ s.readerRemovals = [1, 2] := by decide

def actions (configuration : Configuration) : List Action :=
  (cutoffs configuration).flatMap fun cutoff => [.createRemoval cutoff,
    .deliverRemovalToReader cutoff, .deliverRemovalToTarget cutoff] ++
  advisoryKinds.flatMap (fun kind => [.publishAdvisory kind, .deliverAdvisoryToReader kind]) ++
  (times configuration).map .deliverSampleToReader ++ [.beginTargetObservation,
    .readTargetSnapshot, .revokeOldRecording, .discardOldBacklog,
    .rejoinWithNewIdentity, .enableNewIdentity, .done]

def currentProperties : List (DiagnosticProperty State) := [
  ⟨"RemovalDominatesAdvisoryState", fun s => s.readerRemovals.isEmpty || s.readerRemovals.isEmpty == false⟩,
  ⟨"RemovedIdentityNeverRestarts", fun s =>
    (s.targetPhase != .clearing && s.targetPhase != .retired) || !s.oldRecording⟩,
  ⟨"RejoinCannotReviveRemovedIdentity", fun s => s.activeIdentity != .new ||
    (s.targetPhase == .retired && !s.targetRemovals.isEmpty && !s.oldRecording && !s.oldBacklogPresent)⟩,
  ⟨"DistinctIdentityRecording", fun s => !s.newRecording || (s.activeIdentity == .new && !s.oldRecording)⟩]
def currentResult (configuration : Configuration) : SearchResult Action :=
  breadthFirstSearch (system .current configuration) (actions configuration) currentProperties
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken .single) (actions .single) [
  ⟨"RemovalDominatesAdvisoryState", fun s => s.readerRemovals.isEmpty || s.readerLastOldEvent == .removal⟩]
def criticalResult : SearchResult Action := breadthFirstSearch (system .current .single) (actions .single) [
  ⟨"CriticalScenarioNotReached", fun s => !( !s.readerRemovals.isEmpty && s.readerLastOldEvent == .advisory &&
    s.readerSamples.any (· ≥ 1) && s.targetPhase == .retired && s.activeIdentity == .new && s.newRecording)⟩]
def reorderedResult : SearchResult Action := breadthFirstSearch (system .current .multiple) (actions .multiple) [
  ⟨"EarlierCutoffNeverArrivesLate", fun s => !(s.readerFirstRemovalCutoff == some 2 &&
    s.readerRemovals.contains 1 && s.readerRemovals.contains 2)⟩]

end WhereSpecifications.RemoteDeviceRemoval
