import Protocol

namespace WhereSpecifications.TrackingReconciliation
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Configuration where
  | enabledThenDisabled | denied | repeated | reversed
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive BrokenPhase where | idle | queued | preparing | starting | stopping | done
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def commands : Configuration → List Bool
  | .enabledThenDisabled | .denied => [true, false]
  | .repeated => [true, true, false]
  | .reversed => [false, true]
def authorized : Configuration → Bool
  | .denied => false
  | _ => true

structure State where
  submitted : Nat
  desired : Bool
  persisted : Bool
  controllerChoice : Bool
  ingestorActive : Bool
  published : Bool
  pendingPermission : Option Nat
  queuePending : Bool
  inFlight : Bool
  target : Bool
  settled : Bool
  staleRejected : Bool
  brokenPhase : BrokenPhase
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive Action where
  | submit | brokenBegin | brokenReconcile | brokenCompleteStart | brokenCompleteStop
  | currentPermissionComplete | currentBegin | currentComplete | done
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨0, false, false, false, false, false, none,
  false, false, false, false, false, .idle⟩

def commandAt (configuration : Configuration) (index : Nat) : Bool :=
  (commands configuration)[index]?.getD false

def step (implementation : Implementation) (configuration : Configuration) :
    Action → State → Option State
  | .submit, s =>
      if _h : s.submitted < (commands configuration).length then
        let value := commandAt configuration s.submitted
        let nextID := s.submitted + 1
        if implementation = .broken then some { s with
          submitted := nextID
          desired := value
          settled := false
          brokenPhase := if s.brokenPhase = .idle ∨ s.brokenPhase = .done
            then .queued else s.brokenPhase }
        else some { s with
          submitted := nextID
          desired := value
          persisted := value
          pendingPermission := if value then some nextID else s.pendingPermission
          queuePending := if value then s.queuePending else true
          settled := false }
      else none
  | .brokenBegin, s =>
      if implementation = .broken ∧ s.brokenPhase = .queued then some { s with
        persisted := s.desired
        controllerChoice := s.desired
        ingestorActive := if s.desired then s.ingestorActive else false
        brokenPhase := if s.desired then .preparing else .stopping }
      else none
  | .brokenReconcile, s =>
      if implementation = .broken ∧ s.brokenPhase = .preparing then
        let effective := s.persisted && authorized configuration
        some { s with
          controllerChoice := s.persisted
          ingestorActive := effective
          brokenPhase := if effective then .starting else .stopping }
      else none
  | .brokenCompleteStart, s =>
      if implementation = .broken ∧ s.brokenPhase = .starting then some { s with
        published := true
        settled := if s.submitted = (commands configuration).length then true else false
        brokenPhase := .done }
      else none
  | .brokenCompleteStop, s =>
      if implementation = .broken ∧ s.brokenPhase = .stopping then some { s with
        published := false
        settled := if s.submitted = (commands configuration).length then true else false
        brokenPhase := .done }
      else none
  | .currentPermissionComplete, s =>
      if implementation = .current then match s.pendingPermission with
        | some identifier =>
          let canSettle := identifier ≠ s.submitted ∧
            s.submitted = (commands configuration).length ∧
            s.queuePending = false ∧ s.inFlight = false
          let effective := s.desired && authorized configuration
          some { s with
            pendingPermission := none
            queuePending := if identifier = s.submitted then true else s.queuePending
            staleRejected := s.staleRejected || identifier != s.submitted
            controllerChoice := if canSettle then s.desired else s.controllerChoice
            ingestorActive := if canSettle then effective else s.ingestorActive
            published := if canSettle then effective else s.published
            settled := if canSettle then true else s.settled }
        | none => none
      else none
  | .currentBegin, s =>
      if implementation = .current ∧ s.inFlight = false ∧ s.queuePending then
        let effective := s.desired && authorized configuration
        some { s with
          queuePending := false
          inFlight := true
          controllerChoice := s.desired
          target := effective
          ingestorActive := effective }
      else none
  | .currentComplete, s =>
      if implementation = .current ∧ s.inFlight then
        let finished := decide (s.submitted = (commands configuration).length ∧
          s.pendingPermission = none ∧ s.queuePending = false)
        some { s with
          published := s.target
          inFlight := false
          settled := finished }
      else none
  | .done, s => if s.settled then some s else none

def system (implementation : Implementation) (configuration : Configuration) : TransitionSystem State Action :=
  ⟨[initial], step implementation configuration⟩

def DesiredEffective (configuration : Configuration) (s : State) : Bool :=
  s.desired && authorized configuration
def Quiescent (configuration : Configuration) (s : State) : Prop :=
  s.submitted = (commands configuration).length ∧ s.settled = true
def CurrentIntentIsImmediate (s : State) : Prop := s.persisted = s.desired
def CorrectAtQuiescence (configuration : Configuration) (s : State) : Prop :=
  Quiescent configuration s → s.persisted = s.desired ∧
    s.controllerChoice = s.desired ∧ s.ingestorActive = DesiredEffective configuration s ∧
    s.published = DesiredEffective configuration s
def StalePermissionNotObserved (s : State) : Prop := s.staleRejected = false

def CurrentSafety (configuration : Configuration) (s : State) : Prop :=
  CurrentIntentIsImmediate s ∧ CorrectAtQuiescence configuration s ∧
  (s.settled = true → s.persisted = s.desired ∧ s.controllerChoice = s.desired ∧
    s.ingestorActive = DesiredEffective configuration s ∧
    s.published = DesiredEffective configuration s) ∧
  (s.inFlight = true ∧ s.queuePending = false ∧
      s.pendingPermission ≠ some s.submitted →
    s.controllerChoice = s.desired ∧ s.ingestorActive = DesiredEffective configuration s ∧
    s.target = DesiredEffective configuration s)

private theorem currentPreserved (configuration action before after)
    (safe : CurrentSafety configuration before)
    (transition : (system .current configuration).step action before = some after) :
    CurrentSafety configuration after := by
  cases configuration <;> cases action <;>
    simp [system, step, commands, commandAt, authorized] at transition <;>
    cases hpending : before.pendingPermission <;> (try simp [hpending] at transition) <;>
    (try split at transition) <;>
    simp_all [CurrentSafety, CurrentIntentIsImmediate, CorrectAtQuiescence,
      Quiescent, DesiredEffective, commands, authorized] <;> grind <;> omega

theorem currentSafety (configuration state)
    (reachable : Reachable (system .current configuration) state) :
    CurrentSafety configuration state := by
  apply reachable_invariant (system .current configuration) (CurrentSafety configuration)
    ?_ (currentPreserved configuration) state reachable
  intro candidate member
  simp [system] at member
  subst candidate
  cases configuration <;> simp [CurrentSafety, CurrentIntentIsImmediate,
    CorrectAtQuiescence, Quiescent, DesiredEffective, commands, authorized, initial]

theorem currentIntentIsImmediate (configuration state)
    (h : Reachable (system .current configuration) state) : CurrentIntentIsImmediate state :=
  (currentSafety configuration state h).1
theorem currentCorrectAtQuiescence (configuration state)
    (h : Reachable (system .current configuration) state) : CorrectAtQuiescence configuration state :=
  (currentSafety configuration state h).2.1

def brokenTrace : List Action := [.submit, .brokenBegin, .submit,
  .brokenReconcile, .brokenCompleteStart]
theorem brokenTraceValid :
    (TransitionSystem.run (system .broken .enabledThenDisabled) initial brokenTrace).isSome := by decide
theorem brokenViolatesCorrectAtQuiescence :
    let s := (TransitionSystem.run (system .broken .enabledThenDisabled) initial brokenTrace).get!.getLast!
    s.submitted = 2 ∧ s.settled = true ∧ s.persisted ≠ s.desired := by decide

def staleTrace : List Action := [.submit, .submit, .currentPermissionComplete]
theorem staleTraceValid :
    (TransitionSystem.run (system .current .enabledThenDisabled) initial staleTrace).isSome := by decide
theorem staleTraceViolatesStalePermissionNotObserved :
    (TransitionSystem.run (system .current .enabledThenDisabled) initial staleTrace).get!.getLast!.staleRejected = true := by decide

def actions : List Action := [.submit, .brokenBegin, .brokenReconcile, .brokenCompleteStart,
  .brokenCompleteStop, .currentPermissionComplete, .currentBegin, .currentComplete, .done]
def safetyProperties (configuration : Configuration) : List (DiagnosticProperty State) := [
  ⟨"CurrentIntentIsImmediate", fun s => s.persisted == s.desired⟩,
  ⟨"CorrectAtQuiescence", fun s => !((s.submitted == (commands configuration).length) && s.settled) ||
    (s.persisted == s.desired && s.controllerChoice == s.desired &&
      s.ingestorActive == DesiredEffective configuration s && s.published == DesiredEffective configuration s)⟩]
def currentResult (configuration : Configuration) : SearchResult Action := breadthFirstSearch
  (system .current configuration) actions (safetyProperties configuration)
  (fun s => s.settled) true
def brokenResult : SearchResult Action := breadthFirstSearch
  (system .broken .enabledThenDisabled) actions [
    ⟨"CorrectAtQuiescence", fun s =>
      !((s.submitted == (commands .enabledThenDisabled).length) && s.settled) ||
      (s.persisted == s.desired && s.controllerChoice == s.desired &&
       s.ingestorActive == DesiredEffective .enabledThenDisabled s &&
       s.published == DesiredEffective .enabledThenDisabled s)⟩]
  (fun s => s.settled) true
def staleResult : SearchResult Action := breadthFirstSearch
  (system .current .enabledThenDisabled) actions [
    ⟨"StalePermissionNotObserved", fun s => !s.staleRejected⟩]

end WhereSpecifications.TrackingReconciliation
