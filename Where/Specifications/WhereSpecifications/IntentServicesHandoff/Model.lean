import WhereSpecifications.Protocol

namespace WhereSpecifications.IntentServicesHandoff

open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited

inductive InstallState where | none | installed | cleared
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive ConsumerPhase where | idle | parked | holding | cancelled
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

structure State where
  installed : Bool
  installState : InstallState
  waiterCount : Nat
  consumerPhase : ConsumerPhase
  selfCreated : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive Action where
  | intentFiresEarly | install | clear | installReplace | cancelWaiter | consumerUsesStack
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨false, .none, 0, .idle, false⟩

def step (implementation : Implementation) : Action → State → Option State
  | .intentFiresEarly, s =>
      if s.consumerPhase = .idle then
        if s.installed then some { s with
        consumerPhase := .holding }
        else if implementation = .broken then
          some { s with
        selfCreated := true
        installed := true           
        consumerPhase := .holding
        installState := .installed }
        else some { s with
        consumerPhase := .parked
        waiterCount := s.waiterCount + 1 }
      else none
  | .install, s =>
      if s.installState = .none ∨ s.installState = .cleared then
        if s.waiterCount > 0 then
          some { s with
        installed := true
        installState := .installed           
        consumerPhase := .holding
        waiterCount := s.waiterCount - 1 }
        else some { s with
        installed := true
        installState := .installed }
      else none
  | .clear, s =>
      if s.installed then some { s with
        installed := false
        installState := .cleared       
        consumerPhase := if s.consumerPhase = .holding then .idle else s.consumerPhase }
      else none
  | .installReplace, s =>
      if s.installState = .installed then
        if s.waiterCount > 0 then some { s with
        installed := true         
        consumerPhase := .holding
        waiterCount := s.waiterCount - 1 }
        else some { s with
        installed := true }
      else none
  | .cancelWaiter, s =>
      if s.consumerPhase = .parked ∧ s.waiterCount > 0 then
        some { s with
        consumerPhase := .cancelled
        waiterCount := s.waiterCount - 1 }
      else none
  | .consumerUsesStack, s =>
      if s.consumerPhase = .holding ∧ s.installed then
        some { s with
        consumerPhase := .idle }
      else none

def system (implementation : Implementation) : TransitionSystem State Action :=
  ⟨[initial], step implementation⟩

def NoSelfCreate (s : State) : Prop := s.selfCreated = false
def AtMostOneAuthoritative (s : State) : Prop := s.installed = false ∨ s.installState = .installed
def WaiterExactlyOnce (s : State) : Prop := s.consumerPhase ≠ .parked ∨ s.waiterCount > 0
def AfterClearMustPark (s : State) : Prop := s.consumerPhase = .holding → s.installed = true
def NoMixedWorld (s : State) : Prop := s.consumerPhase = .holding → s.installed = true

def CurrentSafety (s : State) : Prop :=
  NoSelfCreate s ∧ AtMostOneAuthoritative s ∧ WaiterExactlyOnce s ∧
  AfterClearMustPark s ∧ NoMixedWorld s

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, NoSelfCreate, AtMostOneAuthoritative,
      WaiterExactlyOnce, AfterClearMustPark, NoMixedWorld] <;> grind

theorem currentSafety (state) (reachable : Reachable (system .current) state) : CurrentSafety state := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved state reachable
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, NoSelfCreate, AtMostOneAuthoritative,
    WaiterExactlyOnce, AfterClearMustPark, NoMixedWorld, initial]

theorem currentNoSelfCreate (state) (h : Reachable (system .current) state) : NoSelfCreate state :=
  (currentSafety state h).1
theorem currentAtMostOneAuthoritative (state) (h : Reachable (system .current) state) :
    AtMostOneAuthoritative state := (currentSafety state h).2.1
theorem currentWaiterExactlyOnce (state) (h : Reachable (system .current) state) :
    WaiterExactlyOnce state := (currentSafety state h).2.2.1
theorem currentAfterClearMustPark (state) (h : Reachable (system .current) state) :
    AfterClearMustPark state := (currentSafety state h).2.2.2.1
theorem currentNoMixedWorld (state) (h : Reachable (system .current) state) :
    NoMixedWorld state := (currentSafety state h).2.2.2.2

def brokenTrace : List Action := [.intentFiresEarly]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesNoSelfCreate :
    (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!.selfCreated = true := by decide

def actions : List Action := [.intentFiresEarly, .install, .clear, .installReplace,
  .cancelWaiter, .consumerUsesStack]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"NoSelfCreate", fun s => !s.selfCreated⟩,
  ⟨"AtMostOneAuthoritative", fun s => !s.installed || s.installState == .installed⟩,
  ⟨"WaiterExactlyOnce", fun s => s.consumerPhase != .parked || s.waiterCount > 0⟩,
  ⟨"AfterClearMustPark", fun s => s.consumerPhase != .holding || s.installed⟩,
  ⟨"NoMixedWorld", fun s => s.consumerPhase != .holding || s.installed⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"NoSelfCreate", fun s => !s.selfCreated⟩]

end WhereSpecifications.IntentServicesHandoff
