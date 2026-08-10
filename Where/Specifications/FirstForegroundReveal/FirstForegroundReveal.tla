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
RevealStates == {"awaiting", "holding", "revealed"}
Surfaces == {"none", "splash", "content"}

VARIABLES
    reason,
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
    resumeCount

vars == <<reason, runnerPhase, promotionStage, revealState, renderedSurface,
          dirty, installedTaskKey, readyTaskPending, splashObserved,
          sleepingEpoch, holdEpoch, splashSeen, contentBuilt,
          contentRevealCount, splashPhaseRendered, sawCoalescedPromotion,
          resumeCount>>

ReadyVisible == reason = "foreground" /\ runnerPhase = "ready"

TaskIdentity ==
    IF Implementation = "readinessOnly"
        THEN runnerPhase = "ready"
        ELSE ReadyVisible

RunnerShowsSplash == reason = "foreground" /\ runnerPhase = "splash"

SurfaceFor(state) ==
    IF reason = "headless"
        THEN "none"
        ELSE IF runnerPhase = "splash" \/ state # "revealed"
            THEN "splash"
            ELSE "content"

Init ==
    /\ reason = "headless"
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

\* LifecycleRunner.enterForeground() synchronously publishes its foreground
\* reason and launching surface before awaiting the replacement drive.
BeginPromotion ==
    /\ promotionStage = "notStarted"
    /\ reason' = "foreground"
    /\ runnerPhase' = "splash"
    /\ promotionStage' = "promoting"
    /\ dirty' = TRUE
    /\ UNCHANGED <<revealState, renderedSurface, installedTaskKey,
                    readyTaskPending, splashObserved, sleepingEpoch, holdEpoch,
                    splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, sawCoalescedPromotion, resumeCount>>

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
    /\ UNCHANGED <<reason, revealState, renderedSurface, installedTaskKey,
                    readyTaskPending, splashObserved, sleepingEpoch, holdEpoch,
                    splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, resumeCount>>

\* A SwiftUI update reads the runner atomically on the main actor. The
\* onChange body is synchronous, so a newly observed runner splash establishes
\* its hold in this same action. A task identity change schedules, but does not
\* synchronously execute, the ready callback.
Render ==
    /\ dirty
    /\ LET newTaskKey == TaskIdentity
           runnerSplash == RunnerShowsSplash
           splashAppeared == runnerSplash /\ ~splashObserved
           nextReveal == IF splashAppeared THEN "holding" ELSE revealState
           nextHoldEpoch == IF splashAppeared THEN holdEpoch + 1 ELSE holdEpoch
           nextSurface == SurfaceFor(nextReveal)
       IN /\ ~splashAppeared \/ holdEpoch < ArmLimit
          /\ installedTaskKey' = newTaskKey
          /\ readyTaskPending' =
                IF newTaskKey # installedTaskKey
                    THEN ReadyVisible
                    ELSE readyTaskPending
          /\ splashObserved' = runnerSplash
          /\ revealState' = nextReveal
          /\ holdEpoch' = nextHoldEpoch
          /\ renderedSurface' = nextSurface
          /\ splashSeen' = (splashSeen \/ nextSurface = "splash")
          /\ contentBuilt' = (contentBuilt \/ ReadyVisible)
          /\ contentRevealCount' =
                IF nextSurface = "content" /\ renderedSurface # "content"
                    THEN contentRevealCount + 1
                    ELSE contentRevealCount
          /\ splashPhaseRendered' =
                (splashPhaseRendered
                 \/ (reason = "foreground" /\ runnerPhase = "splash"))
    /\ dirty' = FALSE
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, sleepingEpoch,
                    sawCoalescedPromotion, resumeCount>>

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
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, renderedSurface,
                    installedTaskKey, splashObserved, splashSeen, contentBuilt,
                    contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount>>

\* The positive minimum duration is abstracted to one eventual timer action.
\* The production deadline equality guard rejects a completion whose captured
\* epoch was superseded.
TimerExpires ==
    /\ sleepingEpoch > 0
    /\ IF sleepingEpoch = holdEpoch
          THEN /\ revealState' = "revealed"
               /\ dirty' = TRUE
          ELSE /\ revealState' = revealState
               /\ dirty' = dirty
    /\ sleepingEpoch' = 0
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, renderedSurface,
                    installedTaskKey, readyTaskPending, splashObserved,
                    holdEpoch, splashSeen, contentBuilt, contentRevealCount,
                    splashPhaseRendered, sawCoalescedPromotion, resumeCount>>

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
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, splashSeen, contentBuilt,
                    contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion, resumeCount>>

\* Once promoted, ordinary scene background/active cycles do not change the
\* launch reason or runner phase. They may request another render, but the
\* scene-local reveal state must remain revealed.
OrdinaryResume ==
    /\ promotionStage = "complete"
    /\ renderedSurface = "content"
    /\ resumeCount < ResumeLimit
    /\ resumeCount' = resumeCount + 1
    /\ dirty' = TRUE
    /\ UNCHANGED <<reason, runnerPhase, promotionStage, revealState,
                    renderedSurface, installedTaskKey, readyTaskPending,
                    splashObserved, sleepingEpoch, holdEpoch, splashSeen,
                    contentBuilt, contentRevealCount, splashPhaseRendered,
                    sawCoalescedPromotion>>

Idle ==
    /\ promotionStage = "complete"
    /\ ~dirty
    /\ ~readyTaskPending
    /\ sleepingEpoch = 0
    /\ UNCHANGED vars

Next ==
    \/ BeginPromotion
    \/ CompletePromotion
    \/ Render
    \/ StartReadyTask
    \/ TimerExpires
    \/ OverlayRearmsItself
    \/ OrdinaryResume
    \/ Idle

Fairness ==
    /\ WF_vars(CompletePromotion)
    /\ WF_vars(Render)
    /\ WF_vars(StartReadyTask)
    /\ WF_vars(TimerExpires)

Spec == Init /\ [][Next]_vars /\ Fairness

TypeOK ==
    /\ reason \in Reasons
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

HeadlessBuildsNoTree ==
    reason = "headless" => renderedSurface = "none"

ContentRequiresReadyReveal ==
    renderedSurface = "content" => ReadyVisible /\ revealState = "revealed"

FirstRevealWasCovered ==
    contentRevealCount > 0 => splashSeen

CoveredReadyBuildsContent ==
    promotionStage = "complete" /\ renderedSurface = "splash" /\ ~dirty
        => contentBuilt

OneHoldPerFirstReveal ==
    holdEpoch <= 1

NoStrandedReady ==
    ~(promotionStage = "complete"
      /\ renderedSurface = "splash"
      /\ ~dirty
      /\ ~readyTaskPending
      /\ sleepingEpoch = 0)

NoResumeReplay ==
    resumeCount > 0
        => /\ revealState = "revealed"
           /\ contentRevealCount = 1
           /\ holdEpoch = 1

EventuallyFirstReveal ==
    promotionStage = "complete" ~> renderedSurface = "content"

CoalescedPromotionNotReached == ~sawCoalescedPromotion

RenderedRunnerSplashNotReached == ~splashPhaseRendered

RepeatedResumeNotReached == resumeCount < ResumeLimit

====
