import Protocol

namespace WhereSpecifications.LaunchLifecycle
open TransitionSystem

inductive Implementation where | current | broken
deriving DecidableEq, Repr, Inhabited
inductive Reason where | undetermined | userForeground
deriving DecidableEq, BEq, Hashable, Repr, Inhabited
inductive Phase where | notStarted | driving | ready
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

structure State where
  reason : Reason
  phase : Phase
  driveActive : Bool
  memoSyncAuth : Bool
  memoReconcile : Bool
  captureTodayDone : Bool
  syncAuthRuns : Nat
  reconcileRuns : Nat
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

inductive Action where
  | startDrive | runSyncAuth | runReconcileTracking | runCaptureToday
  | enterForeground | reachReady | stutter
deriving DecidableEq, BEq, Hashable, Repr, Inhabited

def initial : State := ⟨.undetermined, .notStarted, false, false, false, false, 0, 0⟩

def step (implementation : Implementation) : Action → State → Option State
  | .startDrive, s => if s.phase = .notStarted then some { s with
        phase := .driving
        driveActive := true } else none
  | .runSyncAuth, s => if s.phase = .driving ∧ s.driveActive ∧
      (implementation = .broken ∨ s.memoSyncAuth = false) then
      some { s with
        memoSyncAuth := true
        syncAuthRuns := s.syncAuthRuns + 1 } else none
  | .runReconcileTracking, s => if s.phase = .driving ∧ s.driveActive ∧
      (implementation = .broken ∨ s.memoReconcile = false) then
      some { s with
        memoReconcile := true
        reconcileRuns := s.reconcileRuns + 1 } else none
  | .runCaptureToday, s => if s.phase = .driving ∧ s.driveActive ∧
      s.reason = .userForeground ∧ s.captureTodayDone = false then
      some { s with
        captureTodayDone := true } else none
  | .enterForeground, s => if s.reason = .undetermined ∧
      (s.phase = .driving ∨ s.phase = .ready) then
      some { s with
        reason := .userForeground
        phase := .driving
        driveActive := true       
        memoSyncAuth := if implementation = .broken then false else s.memoSyncAuth       
        memoReconcile := if implementation = .broken then false else s.memoReconcile } else none
  | .reachReady, s => if s.phase = .driving ∧ s.driveActive ∧ s.memoSyncAuth ∧
      s.memoReconcile ∧ (s.reason = .undetermined ∨ s.captureTodayDone) then
      some { s with
        phase := .ready
        driveActive := false } else none
  | .stutter, s => if s.phase = .ready then some s else none

def system (implementation : Implementation) : TransitionSystem State Action := ⟨[initial], step implementation⟩
def SingleDrive (s : State) : Prop := s.driveActive = false ∨ s.phase = .driving ∨ s.phase = .ready
def MemoNoDoubleRun (s : State) : Prop := s.syncAuthRuns ≤ 1 ∧ s.reconcileRuns ≤ 1
def UndeterminedNoCaptureToday (s : State) : Prop := s.reason = .undetermined → s.captureTodayDone = false
def ForegroundCaptureBeforeReady (s : State) : Prop :=
  s.phase = .ready ∧ s.reason = .userForeground → s.captureTodayDone = true
def CurrentSafety (s : State) : Prop := SingleDrive s ∧ MemoNoDoubleRun s ∧
  UndeterminedNoCaptureToday s ∧ ForegroundCaptureBeforeReady s ∧
  (s.memoSyncAuth = true ↔ s.syncAuthRuns = 1) ∧
  (s.memoReconcile = true ↔ s.reconcileRuns = 1)

private theorem preserved (action before after) (safe : CurrentSafety before)
    (transition : (system .current).step action before = some after) : CurrentSafety after := by
  cases action <;> simp [system, step] at transition <;>
    simp_all [CurrentSafety, SingleDrive, MemoNoDoubleRun,
      UndeterminedNoCaptureToday, ForegroundCaptureBeforeReady] <;> grind <;> omega

theorem currentSafety (state) (reachable : Reachable (system .current) state) : CurrentSafety state := by
  apply reachable_invariant (system .current) CurrentSafety ?_ preserved state reachable
  intro candidate member
  simp [system] at member
  subst candidate
  simp [CurrentSafety, SingleDrive, MemoNoDoubleRun, UndeterminedNoCaptureToday,
    ForegroundCaptureBeforeReady, initial]

theorem currentSingleDrive (s) (h : Reachable (system .current) s) : SingleDrive s := (currentSafety s h).1
theorem currentMemoNoDoubleRun (s) (h : Reachable (system .current) s) : MemoNoDoubleRun s := (currentSafety s h).2.1
theorem currentUndeterminedNoCaptureToday (s) (h : Reachable (system .current) s) :
    UndeterminedNoCaptureToday s := (currentSafety s h).2.2.1
theorem currentForegroundCaptureBeforeReady (s) (h : Reachable (system .current) s) :
    ForegroundCaptureBeforeReady s := (currentSafety s h).2.2.2.1

def brokenTrace : List Action := [.startDrive, .runSyncAuth, .runReconcileTracking,
  .reachReady, .enterForeground, .runSyncAuth]
theorem brokenTraceValid : (TransitionSystem.run (system .broken) initial brokenTrace).isSome := by decide
theorem brokenViolatesMemoNoDoubleRun :
    (TransitionSystem.run (system .broken) initial brokenTrace).get!.getLast!.syncAuthRuns > 1 := by decide

def actions : List Action := [.startDrive, .runSyncAuth, .runReconcileTracking,
  .runCaptureToday, .enterForeground, .reachReady, .stutter]
def currentResult : SearchResult Action := breadthFirstSearch (system .current) actions [
  ⟨"SingleDrive", fun s => !s.driveActive || s.phase == .driving || s.phase == .ready⟩,
  ⟨"MemoNoDoubleRun", fun s => s.syncAuthRuns ≤ 1 && s.reconcileRuns ≤ 1⟩,
  ⟨"UndeterminedNoCaptureToday", fun s => s.reason != .undetermined || !s.captureTodayDone⟩,
  ⟨"ForegroundCaptureBeforeReady", fun s => s.phase != .ready || s.reason != .userForeground || s.captureTodayDone⟩]
def brokenResult : SearchResult Action := breadthFirstSearch (system .broken) actions [
  ⟨"MemoNoDoubleRun", fun s => s.syncAuthRuns ≤ 1 && s.reconcileRuns ≤ 1⟩]

end WhereSpecifications.LaunchLifecycle
