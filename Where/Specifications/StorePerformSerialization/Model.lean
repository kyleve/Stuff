import Protocol

namespace WhereSpecifications.StorePerformSerialization
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited
inductive TaskPhase where | idle | waiting | inPerform | committed
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
structure State where
  isTransacting : Bool
  waiterCount : Nat
  taskAPhase : TaskPhase
  taskBPhase : TaskPhase
  nestedDepth : Nat
  aCommitted : Bool
  bCommitted : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Action where | beginOuterA | beginOuterB | beginNestedSameTask | commitA | commitB | endNested
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨false, 0, .idle, .idle, 0, false, false⟩
def step (implementation : Implementation) : Action → State → Option State
  | .beginOuterA, s => if s.taskAPhase = .idle then
      if s.isTransacting then some { s with
        taskAPhase := .waiting
        waiterCount := s.waiterCount + 1 }
      else some { s with
        taskAPhase := .inPerform
        isTransacting := true } else none
  | .beginOuterB, s => if s.taskBPhase = .idle then
      if implementation = .broken ∧ s.taskAPhase = .inPerform then some { s with
        taskBPhase := .inPerform }
      else if s.isTransacting then some { s with
        taskBPhase := .waiting
        waiterCount := s.waiterCount + 1 }
      else some { s with
        taskBPhase := .inPerform
        isTransacting := true } else none
  | .beginNestedSameTask, s => if s.taskAPhase = .inPerform ∧ s.nestedDepth < 1 then
      some { s with
        nestedDepth := s.nestedDepth + 1 } else none
  | .commitA, s => if s.taskAPhase = .inPerform ∧ s.nestedDepth = 0 then
      if s.waiterCount > 0 then some { s with
        taskAPhase := .committed
        aCommitted := true       
        waiterCount := s.waiterCount - 1
        taskBPhase := .inPerform }
      else some { s with
        taskAPhase := .committed
        aCommitted := true
        isTransacting := false } else none
  | .commitB, s => if s.taskBPhase = .inPerform then
      if s.waiterCount > 0 then some { s with
        taskBPhase := .committed
        bCommitted := true       
        waiterCount := s.waiterCount - 1
        taskAPhase := .inPerform }
      else some { s with
        taskBPhase := .committed
        bCommitted := true
        isTransacting := false } else none
  | .endNested, s => if s.nestedDepth > 0 then some { s with
        nestedDepth := s.nestedDepth - 1 } else none

def system (implementation : Implementation) : TransitionSystem State Action := ⟨[initial], step implementation⟩
def AtMostOneOutermost (s : State) : Prop :=
  s.taskAPhase = .inPerform ∧ s.nestedDepth = 0 → s.taskBPhase ≠ .inPerform
def NestedSameTaskNoWait (s : State) : Prop := s.nestedDepth > 0 → s.taskAPhase = .inPerform
def CurrentSafety (s : State) : Prop := AtMostOneOutermost s ∧ NestedSameTaskNoWait s ∧
  (s.isTransacting = false → s.taskAPhase ≠ .inPerform ∧ s.taskBPhase ≠ .inPerform) ∧
  (s.taskAPhase = .inPerform ∨ s.taskBPhase = .inPerform → s.isTransacting = true) ∧
  s.nestedDepth ≤ 1 ∧
  ¬(s.taskAPhase = .inPerform ∧ s.taskBPhase = .inPerform)

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, AtMostOneOutermost, NestedSameTaskNoWait] <;> grind <;> omega

theorem currentSafety (s) (h : Reachable (system .current) s) : CurrentSafety s := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved s h
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, AtMostOneOutermost, NestedSameTaskNoWait, initial]
theorem currentAtMostOneOutermost (s) (h : Reachable (system .current) s) : AtMostOneOutermost s :=
  (currentSafety s h).1
theorem currentNestedSameTaskNoWait (s) (h : Reachable (system .current) s) : NestedSameTaskNoWait s :=
  (currentSafety s h).2.1

def brokenTrace : List Action := [.beginOuterA, .beginOuterB]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesAtMostOneOutermost :
    let s := (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!
    s.taskAPhase = .inPerform ∧ s.nestedDepth = 0 ∧ s.taskBPhase = .inPerform := by decide

def actions : List Action := [.beginOuterA, .beginOuterB, .beginNestedSameTask, .commitA, .commitB, .endNested]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"AtMostOneOutermost", fun s => s.taskAPhase != .inPerform || s.nestedDepth != 0 || s.taskBPhase != .inPerform⟩,
  ⟨"NestedSameTaskNoWait", fun s => s.nestedDepth == 0 || s.taskAPhase == .inPerform⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"AtMostOneOutermost", fun s => s.taskAPhase != .inPerform || s.nestedDepth != 0 || s.taskBPhase != .inPerform⟩]

end WhereSpecifications.StorePerformSerialization
