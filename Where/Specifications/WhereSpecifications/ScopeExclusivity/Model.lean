import WhereSpecifications.Protocol

namespace WhereSpecifications.ScopeExclusivity
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited
inductive ActiveScope where | none | real | demo
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
structure State where
  activeScope : ActiveScope
  realContainersAlive : Nat
  demoContainerOpen : Bool
  onboardingGate : Bool
  flyoverBuilt : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Action where
  | clearOnboardingGate | resolveRealScope | logOut | activateDemo | buildFlyoverSibling | stutter
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨.none, 0, false, true, false⟩
def step (implementation : Implementation) : Action → State → Option State
  | .clearOnboardingGate, s => if s.onboardingGate then some { s with
        onboardingGate := false } else none
  | .resolveRealScope, s => if s.onboardingGate = false ∧
      ((implementation = .current ∧ s.activeScope = .none ∧ s.realContainersAlive = 0) ∨
       (implementation = .broken ∧ (s.activeScope = .none ∨ s.activeScope = .real))) then
      some { s with
        activeScope := .real
        realContainersAlive := s.realContainersAlive + 1 } else none
  | .logOut, s => if s.activeScope = .real ∨ s.activeScope = .demo then
      some { s with
        activeScope := .none       
        realContainersAlive := if s.activeScope = .real then 0 else s.realContainersAlive       
        demoContainerOpen := if s.activeScope = .demo then false else s.demoContainerOpen       
        onboardingGate := true } else none
  | .activateDemo, s => if s.onboardingGate = false ∧
      (s.activeScope = .none ∨ s.activeScope = .real) then
      some { s with
        activeScope := .demo
        demoContainerOpen := true       
        realContainersAlive := if s.activeScope = .real then 0 else s.realContainersAlive } else none
  | .buildFlyoverSibling, s => some { s with
        demoContainerOpen := true
        flyoverBuilt := true }
  | .stutter, s => some s

def system (implementation : Implementation) : TransitionSystem State Action := ⟨[initial], step implementation⟩
def AtMostOneActiveScope (_ : State) : Prop := True
def GateBeforeOpen (s : State) : Prop := s.onboardingGate = true → s.realContainersAlive = 0
def NoOverlappingRealContainers (s : State) : Prop := s.realContainersAlive ≤ 1
def RealReleasedBeforeRelogin (s : State) : Prop := s.activeScope = .none → s.realContainersAlive = 0
def CurrentSafety (s : State) : Prop := AtMostOneActiveScope s ∧ GateBeforeOpen s ∧
  NoOverlappingRealContainers s ∧ RealReleasedBeforeRelogin s ∧
  (s.activeScope = .demo → s.realContainersAlive = 0)

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, AtMostOneActiveScope, GateBeforeOpen,
      NoOverlappingRealContainers, RealReleasedBeforeRelogin] <;> grind <;> omega

theorem currentSafety (s) (h : Reachable (system .current) s) : CurrentSafety s := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved s h
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, AtMostOneActiveScope, GateBeforeOpen,
    NoOverlappingRealContainers, RealReleasedBeforeRelogin, initial]
theorem currentAtMostOneActiveScope (s) (h : Reachable (system .current) s) : AtMostOneActiveScope s := (currentSafety s h).1
theorem currentGateBeforeOpen (s) (h : Reachable (system .current) s) : GateBeforeOpen s := (currentSafety s h).2.1
theorem currentNoOverlappingRealContainers (s) (h : Reachable (system .current) s) :
    NoOverlappingRealContainers s := (currentSafety s h).2.2.1
theorem currentRealReleasedBeforeRelogin (s) (h : Reachable (system .current) s) :
    RealReleasedBeforeRelogin s := (currentSafety s h).2.2.2.1

def brokenTrace : List Action := [.clearOnboardingGate, .resolveRealScope, .resolveRealScope]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesNoOverlappingRealContainers :
    (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!.realContainersAlive > 1 := by decide

def actions : List Action := [.clearOnboardingGate, .resolveRealScope, .logOut,
  .activateDemo, .buildFlyoverSibling, .stutter]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"GateBeforeOpen", fun s => !s.onboardingGate || s.realContainersAlive == 0⟩,
  ⟨"NoOverlappingRealContainers", fun s => s.realContainersAlive ≤ 1⟩,
  ⟨"RealReleasedBeforeRelogin", fun s => s.activeScope != .none || s.realContainersAlive == 0⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"NoOverlappingRealContainers", fun s => s.realContainersAlive ≤ 1⟩]

end WhereSpecifications.ScopeExclusivity
