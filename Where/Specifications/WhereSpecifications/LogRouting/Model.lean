import WhereSpecifications.Protocol

namespace WhereSpecifications.LogRouting
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited
inductive Scope where | none | real | demo
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive RoutingState where | pending | routing | idleNoStore | idleWithStore
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
structure State where
  activeScope : Scope
  realRouting : RoutingState
  demoRouting : RoutingState
  globalSinkOwner : Scope
  realStoreOpen : Bool
  demoStoreOpen : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Action where | activateReal | activateDemo | deactivateDemo | realStoreOpensLate | demoStoreOpensLate | emitRecord
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨.none, .pending, .pending, .none, false, false⟩
def step (implementation : Implementation) : Action → State → Option State
  | .activateReal, s => some { s with
        activeScope := .real     
        realRouting := if s.realStoreOpen then .routing else .pending     
        globalSinkOwner := if s.realStoreOpen then .real else if s.demoRouting = .routing then .demo else .none     
        demoRouting := if s.demoRouting = .routing then (if s.demoStoreOpen then .idleWithStore else .idleNoStore) else s.demoRouting }
  | .activateDemo, s => some { s with
        activeScope := .demo     
        demoRouting := if s.demoStoreOpen then .routing else .pending     
        globalSinkOwner := if s.demoStoreOpen then .demo else if s.realRouting = .routing then .real else .none     
        realRouting := if s.realRouting = .routing then (if s.realStoreOpen then .idleWithStore else .idleNoStore) else s.realRouting }
  | .deactivateDemo, s => if s.activeScope = .demo then some { s with
        activeScope := .none     
        demoRouting := if s.demoRouting = .routing then (if s.demoStoreOpen then .idleWithStore else .idleNoStore) else s.demoRouting     
        globalSinkOwner := .none } else none
  | .realStoreOpensLate, s => if s.realStoreOpen = false then
      if s.activeScope = .real ∨ implementation = .broken then some { s with
        realStoreOpen := true       
        realRouting := .routing
        globalSinkOwner := .real }
      else some { s with
        realStoreOpen := true
        realRouting := .idleWithStore       
        globalSinkOwner := if s.activeScope = .demo ∧ s.demoRouting = .routing then .demo else .none } else none
  | .demoStoreOpensLate, s => if s.demoStoreOpen = false then
      if s.activeScope = .demo ∨ implementation = .broken then some { s with
        demoStoreOpen := true       
        demoRouting := .routing
        globalSinkOwner := .demo }
      else some { s with
        demoStoreOpen := true
        demoRouting := .idleWithStore       
        globalSinkOwner := if s.activeScope = .real ∧ s.realRouting = .routing then .real else .none } else none
  | .emitRecord, s => if s.globalSinkOwner ≠ .none then some s else none

def system (implementation : Implementation) : TransitionSystem State Action := ⟨[initial], step implementation⟩
def GlobalSinkSingleOwner (s : State) : Prop :=
  s.realRouting = .routing ∨ s.demoRouting = .routing → s.globalSinkOwner = .real ∨ s.globalSinkOwner = .demo
def ShadowedScopeNeverRoutes (s : State) : Prop :=
  (s.activeScope ≠ .real → s.realRouting ≠ .routing) ∧ (s.activeScope ≠ .demo → s.demoRouting ≠ .routing)
def ActiveScopeRecordsReachSink (s : State) : Prop :=
  (s.activeScope = .real → s.realRouting ≠ .routing ∨ s.globalSinkOwner = .real) ∧
  (s.activeScope = .demo → s.demoRouting ≠ .routing ∨ s.globalSinkOwner = .demo)
def CurrentSafety (s : State) : Prop := GlobalSinkSingleOwner s ∧ ShadowedScopeNeverRoutes s ∧ ActiveScopeRecordsReachSink s

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, GlobalSinkSingleOwner, ShadowedScopeNeverRoutes,
      ActiveScopeRecordsReachSink] <;> grind

theorem currentSafety (s) (h : Reachable (system .current) s) : CurrentSafety s := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved s h
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, GlobalSinkSingleOwner, ShadowedScopeNeverRoutes,
    ActiveScopeRecordsReachSink, initial]
theorem currentGlobalSinkSingleOwner (s) (h : Reachable (system .current) s) : GlobalSinkSingleOwner s := (currentSafety s h).1
theorem currentShadowedScopeNeverRoutes (s) (h : Reachable (system .current) s) : ShadowedScopeNeverRoutes s := (currentSafety s h).2.1
theorem currentActiveScopeRecordsReachSink (s) (h : Reachable (system .current) s) : ActiveScopeRecordsReachSink s := (currentSafety s h).2.2

def brokenTrace : List Action := [.activateDemo, .realStoreOpensLate]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesShadowedScopeNeverRoutes :
    let s := (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!
    s.activeScope = .demo ∧ s.realRouting = .routing := by decide

def actions : List Action := [.activateReal, .activateDemo, .deactivateDemo,
  .realStoreOpensLate, .demoStoreOpensLate, .emitRecord]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"GlobalSinkSingleOwner", fun s => (s.realRouting != .routing && s.demoRouting != .routing) ||
    s.globalSinkOwner == .real || s.globalSinkOwner == .demo⟩,
  ⟨"ShadowedScopeNeverRoutes", fun s => (s.activeScope == .real || s.realRouting != .routing) &&
    (s.activeScope == .demo || s.demoRouting != .routing)⟩,
  ⟨"ActiveScopeRecordsReachSink", fun s => (s.activeScope != .real || s.realRouting != .routing || s.globalSinkOwner == .real) &&
    (s.activeScope != .demo || s.demoRouting != .routing || s.globalSinkOwner == .demo)⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"ShadowedScopeNeverRoutes", fun s => (s.activeScope == .real || s.realRouting != .routing) &&
    (s.activeScope == .demo || s.demoRouting != .routing)⟩]

end WhereSpecifications.LogRouting
