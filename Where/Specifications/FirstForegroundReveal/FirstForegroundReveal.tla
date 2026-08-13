---- MODULE FirstForegroundReveal ----
EXTENDS Integers

CONSTANTS Implementation, ResumeLimit, ArmLimit

ASSUME /\ Implementation \in {"current", "readinessOnly", "selfRearming"}
       /\ ResumeLimit \in Nat
       /\ ArmLimit \in Nat
       /\ ArmLimit >= 2

Reasons == {"headless", "foreground"}
RunnerPhases == {"splash", "ready"}
PromotionStages == {"notStarted", "promoting", "complete"}
RevealStates == {"awaiting", "holding", "releasing", "revealed"}
Surfaces == {"none", "splash", "content"}

VARIABLES
    reason,
    sceneActive,
    runnerPhase,
    promotionStage,
    revealState,
    renderedSurface,
    dirty,
    installedTaskKey,
    readyTaskPending,
    splashObserved,
    sleepingEpoch,
    holdEpoch,
    splashSeen,
    contentBuilt,
    contentRevealCount,
    splashPhaseRendered,
    sawCoalescedPromotion,
    resumeCount,
    interruptionCount,
    sawInterruptedFirstReveal

vars == <<reason, sceneActive, runnerPhase, promotionStage, revealState, renderedSurface,
          dirty, installedTaskKey, readyTaskPending, splashObserved,
          sleepingEpoch, holdEpoch, splashSeen, contentBuilt,
          contentRevealCount, splashPhaseRendered, sawCoalescedPromotion,
          resumeCount, interruptionCount, sawInterruptedFirstReveal>>

ReadyTreeEligible == reason = "foreground" /\ runnerPhase = "ready"

ReadyVisible == sceneActive /\ ReadyTreeEligible

TaskIdentity ==
    IF Implementation = "readinessOnly"
        THEN runnerPhase = "ready"
        ELSE ReadyVisible

RunnerShowsSplash == sceneActive /\ reason = "foreground" /\ runnerPhase = "splash"

SurfaceFor(state) ==
    IF reason = "headless" \/ ~sceneActive
        THEN "none"
        ELSE IF runnerPhase = "splash" \/ state \in {"awaiting", "holding"}
            THEN "splash"
            ELSE "content"

Init ==
    /\ reason = "headless"
    /\ sceneActive = FALSE
    /\ runnerPhase = "ready"
    /\ promotionStage = "notStarted"
    /\ revealState = "awaiting"
    /\ renderedSurface = "none"
    /\ dirty = FALSE
    /\ installedTaskKey = TaskIdentity
    /\ readyTaskPending = FALSE
    /\ splashObserved = FALSE
    /\ sleepingEpoch = 0
    /\ holdEpoch = 0
    /\ splashSeen = FALSE
    /\ contentBuilt = FALSE
    /\ contentRevealCount = 0
    /\ splashPhaseRendered = FALSE
    /\ sawCoalescedPromotion = FALSE
    /\ resumeCount = 0
    /\ interruptionCount = 0
    /\ sawInterruptedFirstReveal = FALSE

\* LifecycleRunner.enterForeground() synchronously publishes its foreground
\* reason and launching surface before awaiting the replacement drive.
BeginPromotion ==
    /\ promotionStage = "notStarted"
    /\ reason' = "foreground"
    /\ sceneActive' = TRUE
    /\ runnerPhase' = "splash"
    /\ promotionStage' = "promoting"
    /\ dirty' = TRUE
    /\ UNCHANGED <<revealState, renderedSurface, installedTaskKey,
                    readyTaskPending, splashObserved, sleepingEpoch, holdEpoch,
                    splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, sawCoalescedPromotion, resumeCount,
                    interruptionCount, sawInterruptedFirstReveal>>

\* The foreground drive completes at its next suspension boundary. SwiftUI may
\* render the launching surface before this action, or coalesce both mutations
\* and observe only ready.
CompletePromotion ==
    /\ promotionStage = "promoting"
    /\ runnerPhase' = "ready"
    /\ promotionStage' = "complete"
    /\ dirty' = TRUE
    /\ sawCoalescedPromotion' =
        (sawCoalescedPromotion \/ ~splashPhaseRendered)
    /\ UNCHANGED <<reason, sceneActive, revealState, renderedSurface, installedTaskKey,
                    readyTaskPending, splashObserved, sleepingEpoch, holdEpoch,
                    splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, resumeCount, interruptionCount,
                    sawInterruptedFirstReveal>>

\* The user can leave before the first content reveal. Scene activity is a
\* presentation input independent of the runner's permanently-foreground
\* reason. This model admits one such interruption.
ResignActiveBeforeReveal ==
    /\ sceneActive
    /\ promotionStage # "notStarted"
    /\ contentRevealCount = 0
    /\ interruptionCount = 0
    /\ sceneActive' = FALSE
    /\ interruptionCount' = 1
    /\ sawInterruptedFirstReveal' = TRUE
    /\ dirty' = TRUE
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, holdEpoch, splashSeen,
                    contentBuilt, contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount>>

\* SwiftUI delivers the inactive presentation update before the scene becomes
\* active again. Its render below cancels the keyed task and returns an
\* unrevealed opt-in policy to awaiting.
ReactivateBeforeReveal ==
    /\ ~sceneActive
    /\ ~dirty
    /\ reason = "foreground"
    /\ contentRevealCount = 0
    /\ sceneActive' = TRUE
    /\ dirty' = TRUE
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, holdEpoch, splashSeen,
                    contentBuilt, contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount, interruptionCount,
                    sawInterruptedFirstReveal>>

\* A SwiftUI update reads the runner atomically on the main actor. The
\* onChange body is synchronous, so a newly observed runner splash establishes
\* its hold in this same action. A task identity change schedules, but does not
\* synchronously execute, the ready callback. Committing a releasing content
\* surface also models the reveal marker's onAppear making the reveal sticky.
Render ==
    /\ dirty
    /\ LET newTaskKey == TaskIdentity
           runnerSplash == RunnerShowsSplash
           splashAppeared == runnerSplash /\ ~splashObserved
           revealBeforeSplash ==
                IF ~sceneActive /\ revealState # "revealed"
                    THEN "awaiting"
                    ELSE revealState
           nextReveal == IF splashAppeared THEN "holding" ELSE revealBeforeSplash
           nextHoldEpoch == IF splashAppeared THEN holdEpoch + 1 ELSE holdEpoch
           nextSurface == SurfaceFor(nextReveal)
           committedReveal ==
                nextSurface = "content" /\ nextReveal = "releasing"
           committedRevealState ==
                IF committedReveal THEN "revealed" ELSE nextReveal
       IN /\ ~splashAppeared \/ holdEpoch < ArmLimit
          /\ installedTaskKey' = newTaskKey
          /\ readyTaskPending' =
                IF newTaskKey # installedTaskKey
                    THEN ReadyVisible
                    ELSE readyTaskPending
          /\ splashObserved' = runnerSplash
          /\ sleepingEpoch' =
                IF newTaskKey # installedTaskKey THEN 0 ELSE sleepingEpoch
          /\ revealState' = committedRevealState
          /\ holdEpoch' = nextHoldEpoch
          /\ renderedSurface' = nextSurface
          /\ splashSeen' =
                IF ~sceneActive THEN FALSE ELSE (splashSeen \/ nextSurface = "splash")
          /\ contentBuilt' = (contentBuilt \/ ReadyTreeEligible)
          /\ contentRevealCount' =
                IF nextSurface = "content" /\ renderedSurface # "content"
                    THEN contentRevealCount + 1
                    ELSE contentRevealCount
          /\ splashPhaseRendered' =
                (splashPhaseRendered
                 \/ (sceneActive /\ reason = "foreground" /\ runnerPhase = "splash"))
    /\ dirty' = FALSE
    /\ UNCHANGED <<reason, sceneActive, runnerPhase, promotionStage,
                    sawCoalescedPromotion, resumeCount, interruptionCount,
                    sawInterruptedFirstReveal>>

\* LifecycleContainer's .task body begins after the render that scheduled it.
\* readyBecameVisible arms only the awaiting state; an observed runner splash's
\* earlier deadline is retained.
StartReadyTask ==
    /\ readyTaskPending
    /\ ReadyVisible
    /\ LET armsFirstVisibleReady == revealState = "awaiting"
           nextReveal ==
                IF armsFirstVisibleReady THEN "holding" ELSE revealState
           nextHoldEpoch ==
                IF armsFirstVisibleReady THEN holdEpoch + 1 ELSE holdEpoch
       IN /\ ~armsFirstVisibleReady \/ holdEpoch < ArmLimit
          /\ revealState' = nextReveal
          /\ holdEpoch' = nextHoldEpoch
          /\ sleepingEpoch' =
                IF nextReveal = "holding" THEN nextHoldEpoch ELSE 0
          /\ dirty' = (dirty \/ armsFirstVisibleReady)
    /\ readyTaskPending' = FALSE
    /\ UNCHANGED <<reason, sceneActive, runnerPhase, promotionStage, renderedSurface,
                    installedTaskKey, splashObserved, splashSeen, contentBuilt,
                    contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount, interruptionCount,
                    sawInterruptedFirstReveal>>

\* The positive minimum duration is abstracted to one eventual timer action.
\* The production guards reject a completion whose captured epoch was
\* superseded or whose scene is inactive. A valid completion only releases the
\* overlay; Render commits the visible content frame.
TimerExpires ==
    /\ sleepingEpoch > 0
    /\ IF sleepingEpoch = holdEpoch /\ ReadyVisible
          THEN /\ revealState' = "releasing"
               /\ dirty' = TRUE
          ELSE /\ revealState' = revealState
               /\ dirty' = dirty
    /\ sleepingEpoch' = 0
    /\ UNCHANGED <<reason, sceneActive, runnerPhase, promotionStage, renderedSurface,
                    installedTaskKey, readyTaskPending, splashObserved,
                    holdEpoch, splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, sawCoalescedPromotion, resumeCount,
                    interruptionCount, sawInterruptedFirstReveal>>

\* Negative control: treating the held overlay as a fresh splash appearance
\* lets the overlay renew its own deadline. The sleeping task then carries a
\* stale epoch and no task-identity transition exists to start another timer.
OverlayRearmsItself ==
    /\ Implementation = "selfRearming"
    /\ revealState = "holding"
    /\ renderedSurface = "splash"
    /\ sleepingEpoch > 0
    /\ holdEpoch < ArmLimit
    /\ holdEpoch' = holdEpoch + 1
    /\ dirty' = TRUE
    /\ UNCHANGED <<reason, sceneActive, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, splashSeen, contentBuilt,
                    contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount, interruptionCount,
                    sawInterruptedFirstReveal>>

\* Once promoted, ordinary scene background/active cycles do not change the
\* launch reason or runner phase. They may request another render, but the
\* scene-local reveal state must remain revealed.
OrdinaryResume ==
    /\ promotionStage = "complete"
    /\ sceneActive
    /\ renderedSurface = "content"
    /\ resumeCount < ResumeLimit
    /\ resumeCount' = resumeCount + 1
    /\ dirty' = TRUE
    /\ UNCHANGED <<reason, sceneActive, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, holdEpoch, splashSeen,
                    contentBuilt, contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, interruptionCount,
                    sawInterruptedFirstReveal>>

Idle ==
    /\ promotionStage = "complete"
    /\ ~dirty
    /\ ~readyTaskPending
    /\ sleepingEpoch = 0
    /\ UNCHANGED vars

Next ==
    \/ BeginPromotion
    \/ CompletePromotion
    \/ ResignActiveBeforeReveal
    \/ ReactivateBeforeReveal
    \/ Render
    \/ StartReadyTask
    \/ TimerExpires
    \/ OverlayRearmsItself
    \/ OrdinaryResume
    \/ Idle

Fairness ==
    /\ WF_vars(CompletePromotion)
    /\ WF_vars(ReactivateBeforeReveal)
    /\ WF_vars(Render)
    /\ WF_vars(StartReadyTask)
    /\ WF_vars(TimerExpires)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ reason \in Reasons
    /\ sceneActive \in BOOLEAN
    /\ runnerPhase \in RunnerPhases
    /\ promotionStage \in PromotionStages
    /\ revealState \in RevealStates
    /\ renderedSurface \in Surfaces
    /\ dirty \in BOOLEAN
    /\ installedTaskKey \in BOOLEAN
    /\ readyTaskPending \in BOOLEAN
    /\ splashObserved \in BOOLEAN
    /\ sleepingEpoch \in 0..ArmLimit
    /\ holdEpoch \in 0..ArmLimit
    /\ splashSeen \in BOOLEAN
    /\ contentBuilt \in BOOLEAN
    /\ contentRevealCount \in 0..1
    /\ splashPhaseRendered \in BOOLEAN
    /\ sawCoalescedPromotion \in BOOLEAN
    /\ resumeCount \in 0..ResumeLimit
    /\ interruptionCount \in 0..1
    /\ sawInterruptedFirstReveal \in BOOLEAN

HeadlessBuildsNoTree ==
    reason = "headless" => renderedSurface = "none"

InactiveShowsNothing ==
    ~sceneActive /\ ~dirty => renderedSurface = "none"

ContentRequiresReadyReveal ==
    renderedSurface = "content" => ReadyVisible /\ revealState = "revealed"

FirstRevealWasCovered ==
    contentRevealCount > 0 => splashSeen

CoveredReadyBuildsContent ==
    promotionStage = "complete" /\ renderedSurface = "splash" /\ ~dirty
        => contentBuilt

OneHoldPerFirstReveal ==
    holdEpoch <= interruptionCount + 1

NoStrandedReady ==
    ~(promotionStage = "complete"
      /\ ReadyVisible
      /\ renderedSurface = "splash"
      /\ ~dirty
      /\ ~readyTaskPending
      /\ sleepingEpoch = 0)

NoResumeReplay ==
    resumeCount > 0
        => /\ revealState = "revealed"
           /\ contentRevealCount = 1
           /\ holdEpoch >= 1
           /\ holdEpoch <= interruptionCount + 1

EventuallyFirstReveal ==
    promotionStage = "complete" ~> renderedSurface = "content"

CoalescedPromotionNotReached == ~sawCoalescedPromotion

RenderedRunnerSplashNotReached == ~splashPhaseRendered

RepeatedResumeNotReached == resumeCount < ResumeLimit

InterruptedFirstRevealNotReached == ~sawInterruptedFirstReveal

====
