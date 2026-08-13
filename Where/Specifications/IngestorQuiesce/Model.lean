import Protocol

namespace WhereSpecifications.IngestorQuiesce

open TransitionSystem

inductive Implementation where
  | current
  | broken
deriving DecidableEq, Repr, Inhabited

inductive Phase where
  | idle
  | begin
  | awaiting
  | done
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

structure State where
  acceptsSamples : Bool
  isMonitoring : Bool
  inFlightPersist : Bool
  quiescePhase : Phase
  storeCount : Nat
  sampleDelivered : Bool
  postQuiescePersist : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive Action where
  | streamSample
  | completePersist
  | beginQuiesce
  | awaitInFlight
  | completeQuiesce
  | lateSampleAfterQuiesce
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := {
  acceptsSamples := true
  isMonitoring := true
  inFlightPersist := false
  quiescePhase := .idle
  storeCount := 0
  sampleDelivered := false
  postQuiescePersist := false
}

def step (implementation : Implementation) : Action → State → Option State
  | .streamSample, state =>
      if state.quiescePhase = .idle && !state.inFlightPersist && state.storeCount < 3 then
        some { state with
          sampleDelivered := true
          inFlightPersist := state.acceptsSamples }
      else none
  | .completePersist, state =>
      if state.inFlightPersist then
        some { state with
          inFlightPersist := false
          postQuiescePersist := if state.quiescePhase = .done then true else false
          storeCount := if state.quiescePhase = .done && implementation = .current
            then state.storeCount else state.storeCount + 1 }
      else none
  | .beginQuiesce, state =>
      if state.quiescePhase = .idle then
        some { state with
          quiescePhase := .begin
          acceptsSamples := if implementation = .broken then true else false
          isMonitoring := false }
      else none
  | .awaitInFlight, state =>
      if state.quiescePhase = .begin then
        some { state with quiescePhase := .awaiting }
      else none
  | .completeQuiesce, state =>
      if state.quiescePhase = .awaiting && !state.inFlightPersist then
        some { state with quiescePhase := .done }
      else none
  | .lateSampleAfterQuiesce, state =>
      if state.quiescePhase = .done && !state.inFlightPersist then
        some { state with
          sampleDelivered := true
          inFlightPersist := state.acceptsSamples }
      else none

def system (implementation : Implementation) : TransitionSystem State Action := {
  initial := [initial]
  step := step implementation
}

def NoAcceptAfterQuiesceBegin (state : State) : Prop :=
  state.quiescePhase = .idle ∨ state.acceptsSamples = false

def NoPersistAfterQuiesceDone (state : State) : Prop :=
  state.postQuiescePersist = false

def MonitoringOffAtQuiesceDone (state : State) : Prop :=
  state.quiescePhase ≠ .done ∨ state.isMonitoring = false

private def InductiveStrengthening (state : State) : Prop :=
  (state.quiescePhase ≠ .done ∨ state.inFlightPersist = false) ∧
  (state.quiescePhase = .idle ∨ state.isMonitoring = false)

def CurrentSafety (state : State) : Prop :=
  NoAcceptAfterQuiesceBegin state ∧
  NoPersistAfterQuiesceDone state ∧
  MonitoringOffAtQuiesceDone state ∧
  InductiveStrengthening state

private theorem currentSafetyPreserved (action before after)
    (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) :
    CurrentSafety after := by
  cases action <;>
    simp [system, step] at transition <;>
    simp_all [CurrentSafety, NoAcceptAfterQuiesceBegin,
      NoPersistAfterQuiesceDone, MonitoringOffAtQuiesceDone,
      InductiveStrengthening] <;>
    cases h : before.quiescePhase <;>
    grind

theorem currentSafety (state : State) (reachable : Reachable (system .current) state) :
    CurrentSafety state := by
  apply reachable_invariant (system .current) CurrentSafety ?_ currentSafetyPreserved state reachable
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, NoAcceptAfterQuiesceBegin, NoPersistAfterQuiesceDone,
    MonitoringOffAtQuiesceDone, InductiveStrengthening, initial]

theorem currentNoAcceptAfterQuiesceBegin (state : State)
    (reachable : Reachable (system .current) state) : NoAcceptAfterQuiesceBegin state :=
  (currentSafety state reachable).1

theorem currentNoPersistAfterQuiesceDone (state : State)
    (reachable : Reachable (system .current) state) : NoPersistAfterQuiesceDone state :=
  (currentSafety state reachable).2.1

theorem currentMonitoringOffAtQuiesceDone (state : State)
    (reachable : Reachable (system .current) state) : MonitoringOffAtQuiesceDone state :=
  (currentSafety state reachable).2.2.1

def brokenTrace : List Action :=
  [.beginQuiesce, .awaitInFlight, .completeQuiesce,
   .lateSampleAfterQuiesce, .completePersist]

theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by
  decide

theorem brokenViolatesNoPersistAfterQuiesceDone :
    (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!.postQuiescePersist = true := by
  decide

def actions : List Action :=
  [.streamSample, .completePersist, .beginQuiesce, .awaitInFlight,
   .completeQuiesce, .lateSampleAfterQuiesce]

def currentResult : SearchResult Action :=
  breadthFirstSearch (system .current) actions [
    { name := "NoAcceptAfterQuiesceBegin", holds := fun state =>
        state.quiescePhase == .idle || !state.acceptsSamples },
    { name := "NoPersistAfterQuiesceDone", holds := fun state =>
        !state.postQuiescePersist },
    { name := "MonitoringOffAtQuiesceDone", holds := fun state =>
        state.quiescePhase != .done || !state.isMonitoring }
  ]

def brokenResult : SearchResult Action :=
  breadthFirstSearch (system .broken) actions [
    { name := "NoPersistAfterQuiesceDone", holds := fun state =>
        !state.postQuiescePersist }
  ]

end WhereSpecifications.IngestorQuiesce
