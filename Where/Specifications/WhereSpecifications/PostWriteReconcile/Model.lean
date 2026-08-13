import WhereSpecifications.Protocol

namespace WhereSpecifications.PostWriteReconcile
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited
inductive WritePhase where | idle | inPerform | committed
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive ReconcilePhase where | none | invalidating | reminders | widgets | done
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
structure State where
  writePhase : WritePhase
  reconcilePhase : ReconcilePhase
  changesPinged : Bool
  sideEffectsApplied : Bool
  readerSawPing : Bool
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Action where
  | beginPerform | commit | stepInvalidate | stepReminders | stepWidgets
  | pingChanges | readerRefresh | resetPath
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨.idle, .none, false, false, false⟩
def step (implementation : Implementation) : Action → State → Option State
  | .beginPerform, s => if s.writePhase = .idle then some { s with
        writePhase := .inPerform } else none
  | .commit, s => if s.writePhase = .inPerform then some { s with
        writePhase := .committed     
        reconcilePhase := .invalidating } else none
  | .stepInvalidate, s => if s.reconcilePhase = .invalidating then some { s with
        reconcilePhase := .reminders } else none
  | .stepReminders, s => if s.reconcilePhase = .reminders then some { s with
        reconcilePhase := .widgets } else none
  | .stepWidgets, s => if s.reconcilePhase = .widgets then some { s with
        reconcilePhase := .done     
        sideEffectsApplied := true } else none
  | .pingChanges, s => if s.writePhase = .committed ∧
      (implementation = .broken ∨ s.reconcilePhase = .done) then some { s with
        changesPinged := true } else none
  | .readerRefresh, s => if s.changesPinged then some { s with
        readerSawPing := true } else none
  | .resetPath, s => if s.writePhase = .committed then some initial else none

def system (implementation : Implementation) : TransitionSystem State Action := ⟨[initial], step implementation⟩
def NoChangesBeforeReconcileDone (s : State) : Prop := s.changesPinged = true → s.reconcilePhase = .done
def BrokenNoEarlyPing := NoChangesBeforeReconcileDone
def ReaderSeesAppliedSideEffects (s : State) : Prop := s.readerSawPing = true → s.sideEffectsApplied = true
def CurrentSafety (s : State) : Prop := NoChangesBeforeReconcileDone s ∧ ReaderSeesAppliedSideEffects s ∧
  (s.changesPinged = true → s.sideEffectsApplied = true) ∧
  (s.writePhase = .idle ∨ s.writePhase = .inPerform →
    s.changesPinged = false ∧ s.sideEffectsApplied = false ∧ s.readerSawPing = false) ∧
  (s.reconcilePhase ≠ .none → s.writePhase = .committed) ∧
  (s.reconcilePhase = .done → s.sideEffectsApplied = true)

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, NoChangesBeforeReconcileDone, ReaderSeesAppliedSideEffects, initial] <;>
    grind

theorem currentSafety (s) (h : Reachable (system .current) s) : CurrentSafety s := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved s h
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, NoChangesBeforeReconcileDone, ReaderSeesAppliedSideEffects, initial]
theorem currentNoChangesBeforeReconcileDone (s) (h : Reachable (system .current) s) :
    NoChangesBeforeReconcileDone s := (currentSafety s h).1
theorem currentReaderSeesAppliedSideEffects (s) (h : Reachable (system .current) s) :
    ReaderSeesAppliedSideEffects s := (currentSafety s h).2.1

def brokenTrace : List Action := [.beginPerform, .commit, .pingChanges]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesBrokenNoEarlyPing :
    let s := (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!
    s.changesPinged = true ∧ s.reconcilePhase ≠ .done := by decide

def actions : List Action := [.beginPerform, .commit, .stepInvalidate, .stepReminders,
  .stepWidgets, .pingChanges, .readerRefresh, .resetPath]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"NoChangesBeforeReconcileDone", fun s => !s.changesPinged || s.reconcilePhase == .done⟩,
  ⟨"ReaderSeesAppliedSideEffects", fun s => !s.readerSawPing || s.sideEffectsApplied⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"BrokenNoEarlyPing", fun s => !s.changesPinged || s.reconcilePhase == .done⟩]

end WhereSpecifications.PostWriteReconcile
