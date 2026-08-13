import Std

namespace WhereSpecifications

/-- A finite, executable labelled transition system. -/
structure TransitionSystem (State Action : Type) where
  initial : List State
  step : Action → State → Option State

namespace TransitionSystem

variable {State Action : Type}

def Enabled (system : TransitionSystem State Action) (action : Action) (state : State) : Prop :=
  (system.step action state).isSome

inductive Reachable (system : TransitionSystem State Action) : State → Prop where
  | initial {state} : state ∈ system.initial → Reachable system state
  | step {before after action} :
      Reachable system before →
      system.step action before = some after →
      Reachable system after

def run (system : TransitionSystem State Action) (start : State) : List Action → Option (List State)
  | [] => some [start]
  | action :: rest => do
      let next ← system.step action start
      let tail ← run system next rest
      pure (start :: tail)

structure Trace (system : TransitionSystem State Action) where
  start : State
  actions : List Action
  startsInitial : start ∈ system.initial
  valid : (run system start actions).isSome

/-- Infinite state behavior whose steps are transitions or explicit stutters. -/
structure Behavior (system : TransitionSystem State Action) where
  state : Nat → State
  startsInitial : state 0 ∈ system.initial
  advances : ∀ index, state (index + 1) = state index ∨
    ∃ action, system.step action (state index) = some (state (index + 1))

def Occurs (system : TransitionSystem State Action)
    (behavior : Behavior system) (action : Action) (index : Nat) : Prop :=
  system.step action (behavior.state index) = some (behavior.state (index + 1))

/-- TLA-style weak fairness: a continuously enabled action eventually occurs. -/
def WeakFair (system : TransitionSystem State Action)
    (behavior : Behavior system) (action : Action) : Prop :=
  ∀ start,
    (∀ index, start ≤ index → Enabled system action (behavior.state index)) →
    ∃ index, start ≤ index ∧ Occurs system behavior action index

def Eventually (system : TransitionSystem State Action)
    (behavior : Behavior system) (property : State → Prop) (start : Nat) : Prop :=
  ∃ index, start ≤ index ∧ property (behavior.state index)

def LeadsTo (system : TransitionSystem State Action)
    (behavior : Behavior system) (before after : State → Prop) : Prop :=
  ∀ start, before (behavior.state start) → Eventually system behavior after start

theorem reachable_invariant
    (system : TransitionSystem State Action)
    (invariant : State → Prop)
    (initial : ∀ state, state ∈ system.initial → invariant state)
    (preserved : ∀ action before after,
      invariant before → system.step action before = some after → invariant after) :
    ∀ state, Reachable system state → invariant state := by
  intro state reachable
  induction reachable with
  | initial member => exact initial _ member
  | step reachable transition ih => exact preserved _ _ _ ih transition

structure DiagnosticProperty (State : Type) where
  name : String
  holds : State → Bool

structure SearchNode (State Action : Type) where
  state : State
  actions : List Action
  depth : Nat

inductive SearchOutcome (Action : Type) where
  | complete
  | invariantViolation (property : String) (trace : List Action)
  | deadlock (trace : List Action)
  | stateLimitReached
deriving Repr, Inhabited

structure SearchResult (Action : Type) where
  generatedStates : Nat
  distinctStates : Nat
  maximumDepth : Nat
  outcome : SearchOutcome Action
deriving Repr, Inhabited

inductive ExpectedOutcome where
  | pass
  | violation (property : String)

def reportCase [Repr Action] (caseName : String) (expected : ExpectedOutcome)
    (result : SearchResult Action) : IO Bool := do
  let counts := s!"{result.distinctStates} distinct, {result.generatedStates} generated, depth {result.maximumDepth}"
  match expected, result.outcome with
  | .pass, .complete =>
      IO.println s!"  ok   {caseName} (pass; {counts})"
      pure true
  | .violation expectedProperty, .invariantViolation actualProperty trace =>
      if expectedProperty = actualProperty then
        IO.println s!"  ok   {caseName} (expected {actualProperty}; {counts})"
        IO.println s!"       trace: {reprStr trace}"
        pure true
      else
        IO.eprintln s!"  FAIL {caseName}: expected {expectedProperty}, got {actualProperty}"
        pure false
  | _, .deadlock trace =>
      IO.eprintln s!"  FAIL {caseName}: unexpected deadlock after {reprStr trace}"
      pure false
  | _, .stateLimitReached =>
      IO.eprintln s!"  FAIL {caseName}: diagnostic state limit reached"
      pure false
  | .pass, .invariantViolation property trace =>
      IO.eprintln s!"  FAIL {caseName}: unexpected {property} after {reprStr trace}"
      pure false
  | .violation property, .complete =>
      IO.eprintln s!"  FAIL {caseName}: expected {property}, search completed cleanly"
      pure false

private def firstViolation (properties : List (DiagnosticProperty State)) (state : State) : Option String :=
  properties.findSome? fun property =>
    if property.holds state then none else some property.name

/-- Exact breadth-first exploration. Hashes index the set, while `BEq` resolves collisions. -/
partial def breadthFirstSearch
    [BEq State] [Hashable State]
    (system : TransitionSystem State Action)
    (actions : List Action)
    (properties : List (DiagnosticProperty State))
    (terminal : State → Bool := fun _ => false)
    (checkDeadlock : Bool := false)
    (stateLimit : Nat := 2_000_000) : SearchResult Action :=
  let initialNodes := system.initial.map fun state =>
    { state, actions := [], depth := 0 : SearchNode State Action }
  let initialSeen := system.initial.foldl (fun seen state => seen.insert state)
    (Std.HashSet.emptyWithCapacity system.initial.length)
  loop initialNodes.toArray 0 initialSeen system.initial.length system.initial.length 0
where
  loop (queue : Array (SearchNode State Action)) (cursor : Nat)
      (seen : Std.HashSet State) (generated distinct maximumDepth : Nat) : SearchResult Action :=
    if distinct > stateLimit then
      { generatedStates := generated, distinctStates := distinct, maximumDepth, outcome := .stateLimitReached }
    else if h : cursor < queue.size then
      let node := queue[cursor]
      match firstViolation properties node.state with
      | some property =>
          { generatedStates := generated, distinctStates := distinct, maximumDepth,
            outcome := .invariantViolation property node.actions }
      | none =>
          let successors := actions.filterMap fun action =>
            (system.step action node.state).map fun state => (action, state)
          if checkDeadlock && successors.isEmpty && !terminal node.state then
            { generatedStates := generated, distinctStates := distinct, maximumDepth,
              outcome := .deadlock node.actions }
          else
            let (queue, seen, distinct, maximumDepth) := successors.foldl
              (fun (queue, seen, distinct, maximumDepth) (action, state) =>
                if seen.contains state then
                  (queue, seen, distinct, maximumDepth)
                else
                  let nextDepth := node.depth + 1
                  (queue.push { state, actions := node.actions ++ [action], depth := nextDepth },
                   seen.insert state, distinct + 1, max maximumDepth nextDepth))
              (queue, seen, distinct, maximumDepth)
            loop queue (cursor + 1) seen (generated + successors.length) distinct maximumDepth
    else
      { generatedStates := generated, distinctStates := distinct, maximumDepth,
        outcome := .complete }

end TransitionSystem

end WhereSpecifications
