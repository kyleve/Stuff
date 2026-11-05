---- MODULE RecordingHistorySelection ----
EXTENDS FiniteSets, Integers

CONSTANTS Implementation, Scenario, TimeCount, ReplicaCount, ChangeContext, ExportEnabled, IncludeIgnore
ASSUME /\ Implementation \in {"current", "prune-raw", "fill-gap", "viewer-day", "major-cache",
                              "query-cache", "group-other", "continuous-day", "drop-candidate", "split-export",
                              "drop-issue", "ignore-explicit", "policy-choice"}
       /\ Scenario \in {"regions", "days", "unknown"}
       /\ TimeCount \in {1, 2, 3}
       /\ ReplicaCount \in {1, 2}
       /\ ChangeContext \in BOOLEAN
       /\ ExportEnabled \in BOOLEAN
       /\ IncludeIgnore \in BOOLEAN

Replicas == 1..ReplicaCount
Times == 0..(TimeCount - 1)
Days == {1, 2}
Devices == {"A", "B"}
Observations == [device : Devices, instant : Times]
Controls == {"dayA", "periodB"} \cup (IF IncludeIgnore THEN {"ignoreA"} ELSE {})
Queries == {Days, {1}, {2}}
DayScope == Times \cap {0, 2}
PeriodScope == {TimeCount - 1}
At(evidence, instant) == {item \in evidence : item.instant = instant}

\* The ID also identifies a fixed immutable observation. Zero means unknown, not a date/region.
Day(item) ==
    CASE Scenario = "days" -> IF item.instant = 1 \/ (item.instant = 0 /\ item.device = "B") THEN 2 ELSE 1
      [] Scenario = "unknown" /\ item.instant = 1 /\ item.device = "A" -> 0
      [] OTHER -> 1
Geography(item) ==
    CASE Scenario = "unknown" /\ item.instant = 0 -> 0
      [] Scenario = "days" /\ item.instant \in {0, 1} -> 1
      [] item.instant = 0 /\ item.device = "B" -> 2
      [] OTHER -> 1
KnownDays(evidence) == {Day(item) : item \in evidence} \ {0}

Choices(controls, instant) ==
    (IF "dayA" \in controls /\ instant \in DayScope THEN {"A"} ELSE {}) \cup
    (IF "periodB" \in controls /\ instant \in PeriodScope THEN {"B"} ELSE {})
AppliedChoices(controls, instant) ==
    IF Implementation = "continuous-day" /\ "dayA" \in controls
    THEN Choices(controls, instant) \cup {"A"} ELSE Choices(controls, instant)
AutomaticEvidence(evidence, controls, instant) ==
    {item \in At(evidence, instant) : ~("ignoreA" \in controls /\ instant = 0 /\ item.device = "A")}
RelevantEvidence(evidence, controls, instant) ==
    IF AppliedChoices(controls, instant) = {} \/ Implementation = "ignore-explicit"
    THEN AutomaticEvidence(evidence, controls, instant) ELSE At(evidence, instant)
ComparisonRegion(item) == IF Implementation = "group-other" THEN 1 ELSE Geography(item)
Statuses == {"empty", "chosen", "onlyAvailable", "choiceConflict", "dayConflict", "unknownDay",
             "regionConflict", "moving", "agreement", "uncertain"}
Unresolved == {"choiceConflict", "dayConflict", "unknownDay", "regionConflict"}

Segment(evidence, controls, version, instant) ==
    LET available == RelevantEvidence(evidence, controls, instant)
        choices == AppliedChoices(controls, instant)
        chosen == {item \in available : item.device \in choices}
        regions == {ComparisonRegion(item) : item \in available}
    IN IF Cardinality(choices) > 1
       THEN [status |-> "choiceConflict", selected |-> {}]
       ELSE IF choices # {}
       THEN LET admitted == IF Implementation = "policy-choice" /\ version = 2 THEN {}
                            ELSE IF Implementation = "fill-gap" /\ chosen = {} THEN available ELSE chosen
            IN [status |-> "chosen", selected |-> admitted]
       ELSE IF available = {} THEN [status |-> "empty", selected |-> {}]
       ELSE IF Cardinality(available) = 1 THEN [status |-> "onlyAvailable", selected |-> available]
       ELSE IF 0 \in {Day(item) : item \in available}
       THEN [status |-> "unknownDay", selected |-> {}]
       ELSE IF Cardinality(KnownDays(available)) > 1
       THEN [status |-> "dayConflict", selected |-> {}]
       ELSE IF 0 \in regions THEN [status |-> "uncertain", selected |-> available]
       ELSE IF Cardinality(regions) > 1
       THEN IF version = 2 /\ instant = 0
            THEN [status |-> "moving", selected |-> {item \in available : item.device = "A"}]
            ELSE [status |-> "regionConflict", selected |-> {}]
       ELSE [status |-> "agreement", selected |-> available]

DeclaredDays(controls, instant) ==
    IF Scenario = "days" /\ "dayA" \in controls /\ instant \in DayScope THEN {1} ELSE {}
IssueEvidence(evidence, controls, version, instant) ==
    LET segment == Segment(evidence, controls, version, instant)
    IN IF segment.status = "chosen" THEN {item \in segment.selected : Day(item) = 0}
       ELSE RelevantEvidence(evidence, controls, instant)
Candidates(evidence, controls, version, instant) ==
    IF Segment(evidence, controls, version, instant).status = "chosen" THEN {}
    ELSE KnownDays(RelevantEvidence(evidence, controls, instant)) \cup DeclaredDays(controls, instant)
HasUnknown(evidence, controls, version, instant) ==
    LET segment == Segment(evidence, controls, version, instant)
    IN IF segment.status = "chosen"
       THEN \E item \in segment.selected : Day(item) = 0
       ELSE (\E item \in RelevantEvidence(evidence, controls, instant) : Day(item) = 0) \/
            (segment.status = "choiceConflict" /\ At(evidence, instant) = {})
IsIssue(evidence, controls, version, instant) ==
    Segment(evidence, controls, version, instant).status \in Unresolved \/
    HasUnknown(evidence, controls, version, instant)
Selected(evidence, controls, version) ==
    UNION {Segment(evidence, controls, version, instant).selected : instant \in Times}

Resolve(evidence, controls, version, query, zone) ==
    LET selected == Selected(evidence, controls, version)
        contributing == {item \in selected : Day(item) \in query}
        issues == {instant \in Times : IsIssue(evidence, controls, version, instant) /\
                    ~(Implementation = "drop-issue" /\ query = Days /\
                      Segment(evidence, controls, version, instant).status = "regionConflict") /\
                    (Candidates(evidence, controls, version, instant) \cap query # {} \/
                     HasUnknown(evidence, controls, version, instant))}
    IN [raw |-> IF Implementation = "prune-raw" THEN selected ELSE evidence,
        version |-> version, query |-> query,
        contributions |-> {[observation |-> item,
                            day |-> IF Implementation = "viewer-day" THEN Day(item) + zone ELSE Day(item)]
                           : item \in contributing},
        segments |-> [instant \in Times |-> Segment(evidence, controls, version, instant)],
        issues |-> issues,
        candidates |-> [instant \in issues |->
            IF Implementation = "drop-candidate" THEN {} ELSE Candidates(evidence, controls, version, instant)],
        unassigned |-> {instant \in issues : HasUnknown(evidence, controls, version, instant)}]

HasExclusiveGap(evidence, controls) ==
    /\ controls = {"dayA"}
    /\ [device |-> "B", instant |-> 0] \in evidence
    /\ [device |-> "A", instant |-> 0] \notin evidence

(* --algorithm RecordingHistorySelectionAlgorithm {
variables received = [replica \in Replicas |-> {}],
          controls = [replica \in Replicas |-> {}],
          versions = [replica \in Replicas |-> 1],
          queries = [replica \in Replicas |-> Days],
          zones = [replica \in Replicas |-> 0],
          views = [replica \in Replicas |-> Resolve({}, {}, 1, Days, 0)],
          sawGap = [replica \in Replicas |-> FALSE],
          sawIgnoreBeforeA = [replica \in Replicas |-> FALSE],
          prepared = [replica \in Replicas |-> {}],
          published = [replica \in Replicas |-> {}];

macro Refresh(evidence, decisions, policy, query, zone) {
    with (next = Resolve(evidence, decisions, policy, query, zone)) {
        received[self] := evidence || controls[self] := decisions ||
        versions[self] := policy || queries[self] := query || zones[self] := zone ||
        sawGap[self] := sawGap[self] \/ HasExclusiveGap(evidence, decisions) ||
        sawIgnoreBeforeA[self] := sawIgnoreBeforeA[self] \/
            ("ignoreA" \in decisions /\ [device |-> "A", instant |-> 0] \notin evidence) ||
        views[self] :=
            IF (Implementation = "major-cache" /\ policy # versions[self]) \/
               (Implementation = "query-cache" /\ query # queries[self])
            THEN views[self] ELSE next;
    };
}

process (Replica \in Replicas) {
Act:
    while (TRUE) {
        either {
            with (item \in Observations) {
                Refresh(received[self] \cup {item}, controls[self], versions[self], queries[self], zones[self]);
            };
        } or {
            with (control \in Controls) {
                Refresh(received[self], controls[self] \cup {control}, versions[self], queries[self], zones[self]);
            };
        } or {
            await ChangeContext;
            with (version \in {1, 2}) {
                Refresh(received[self], controls[self], version, queries[self], zones[self]);
            };
        } or {
            await ChangeContext;
            with (query \in Queries) {
                Refresh(received[self], controls[self], versions[self], query, zones[self]);
            };
        } or {
            await ChangeContext;
            Refresh(received[self], controls[self], versions[self], queries[self], 1 - zones[self]);
        } or {
            await ExportEnabled /\ prepared[self] = {} /\
                  views[self].issues = {} /\ views[self].contributions # {};
            prepared[self] := {views[self]};
        } or {
            await ExportEnabled /\ prepared[self] # {} /\ published[self] = {};
            published[self] := IF Implementation = "split-export" THEN {views[self]} ELSE prepared[self];
        };
    }
}
} *)

TypeOK ==
    /\ received \in [Replicas -> SUBSET Observations]
    /\ controls \in [Replicas -> SUBSET Controls]
    /\ versions \in [Replicas -> {1, 2}]
    /\ queries \in [Replicas -> Queries]
    /\ zones \in [Replicas -> {0, 1}]
    /\ sawGap \in [Replicas -> BOOLEAN]
    /\ sawIgnoreBeforeA \in [Replicas -> BOOLEAN]
    /\ DOMAIN prepared = Replicas
    /\ DOMAIN published = Replicas
    /\ \A replica \in Replicas :
        /\ Cardinality(prepared[replica]) <= 1
        /\ Cardinality(published[replica]) <= 1
        /\ views[replica].raw \subseteq Observations
        /\ views[replica].version \in {1, 2}
        /\ views[replica].query \in Queries
        /\ views[replica].contributions \subseteq [observation : Observations, day : 1..3]
        /\ views[replica].segments \in [Times -> [status : Statuses, selected : SUBSET Observations]]
        /\ views[replica].issues \subseteq Times
        /\ views[replica].candidates \in [views[replica].issues -> SUBSET Days]
        /\ views[replica].unassigned \subseteq views[replica].issues

RawObservationsSurvive == \A replica \in Replicas : views[replica].raw = received[replica]
FullPolicyMatches == \A replica \in Replicas : views[replica].version = versions[replica]
QueryMatches == \A replica \in Replicas : views[replica].query = queries[replica]
LogicalDaysSurvive ==
    \A replica \in Replicas : \A contribution \in views[replica].contributions :
        /\ contribution.day = Day(contribution.observation)
        /\ contribution.day \in queries[replica]
EqualInputsConverge ==
    \A left, right \in Replicas :
        received[left] = received[right] /\ controls[left] = controls[right] /\
        versions[left] = versions[right] /\ queries[left] = queries[right]
        => views[left] = views[right]
ExclusiveChoicesNeverFillGaps ==
    \A replica \in Replicas, instant \in Times :
        Cardinality(Choices(controls[replica], instant)) = 1
        => \A item \in views[replica].segments[instant].selected :
            item.device \in Choices(controls[replica], instant)
ExplicitChoicesKeepTheirAvailableEvidence ==
    \A replica \in Replicas, instant \in Times :
        Cardinality(Choices(controls[replica], instant)) = 1
        => /\ views[replica].segments[instant].status = "chosen"
           /\ views[replica].segments[instant].selected =
                {item \in At(received[replica], instant) : item.device \in Choices(controls[replica], instant)}
HistoricalIgnoreExcludesLateAutomaticEvidence ==
    \A replica \in Replicas :
        "ignoreA" \in controls[replica] /\ Choices(controls[replica], 0) = {}
        => \A item \in views[replica].segments[0].selected : item.device # "A"
WholeDayLeavesInterveningDate ==
    \A replica \in Replicas :
        Scenario = "days" /\ TimeCount = 3 /\ controls[replica] = {"dayA"}
        => views[replica].segments[1].selected = At(received[replica], 1)
WholeDayAndFixedPeriodOverlap ==
    \A replica \in Replicas :
        TimeCount = 3 /\ {"dayA", "periodB"} \subseteq controls[replica]
        => /\ views[replica].segments[0].status = "chosen"
           /\ views[replica].segments[2].status = "choiceConflict"
           /\ views[replica].segments[2].selected = {}
SpecificGeographyBeforeGrouping ==
    \A replica \in Replicas, instant \in Times :
        LET evidence == AutomaticEvidence(received[replica], controls[replica], instant)
            regions == {Geography(item) : item \in evidence}
        IN Choices(controls[replica], instant) = {} /\ versions[replica] = 1 /\
           regions = {1, 2} /\ Cardinality(KnownDays(evidence)) = 1
           => /\ views[replica].segments[instant].status = "regionConflict"
              /\ views[replica].segments[instant].selected = {}
GeographicConflictStaysIncomplete ==
    \A replica \in Replicas, instant \in Times :
        LET evidence == AutomaticEvidence(received[replica], controls[replica], instant)
        IN Choices(controls[replica], instant) = {} /\ versions[replica] = 1 /\
           {Geography(item) : item \in evidence} = {1, 2} /\
           KnownDays(evidence) \cap queries[replica] # {}
           => /\ instant \in views[replica].issues
              /\ KnownDays(evidence) \subseteq views[replica].candidates[instant]
UnknownGeographyIsNeitherAgreementNorConflict ==
    \A replica \in Replicas, instant \in Times :
        LET evidence == AutomaticEvidence(received[replica], controls[replica], instant)
        IN Choices(controls[replica], instant) = {} /\ evidence # {} /\
           {Geography(item) : item \in evidence} = {0} /\ {Day(item) : item \in evidence} = {1} /\
           Cardinality(evidence) > 1
           => /\ views[replica].segments[instant].status = "uncertain"
              /\ views[replica].segments[instant].selected = evidence
DisputedDayLabelsNeedAChoice ==
    \A replica \in Replicas, instant \in Times :
        Choices(controls[replica], instant) = {} /\
        KnownDays(AutomaticEvidence(received[replica], controls[replica], instant)) = Days
        => /\ views[replica].segments[instant].selected = {}
           /\ instant \in views[replica].issues
           /\ views[replica].candidates[instant] = Days
UnknownAssignmentsCannotPromoteARival ==
    \A replica \in Replicas, instant \in Times :
        Choices(controls[replica], instant) = {} /\
        (\E item \in AutomaticEvidence(received[replica], controls[replica], instant) : Day(item) = 0)
        => /\ (Cardinality(AutomaticEvidence(received[replica], controls[replica], instant)) > 1
               => views[replica].segments[instant].selected = {})
           /\ instant \in views[replica].unassigned
CandidateDaysRemain ==
    \A replica \in Replicas : \A instant \in views[replica].issues :
        KnownDays(IssueEvidence(received[replica], controls[replica], versions[replica], instant))
        \subseteq views[replica].candidates[instant]
IndependentPresenceSurvives ==
    \A replica \in Replicas, instant \in Times :
        LET evidence == AutomaticEvidence(received[replica], controls[replica], instant)
        IN Choices(controls[replica], instant) = {} /\ evidence # {} /\
           {Day(item) : item \in evidence} = {1} /\ {Geography(item) : item \in evidence} = {1} /\
           1 \in queries[replica]
           => \A item \in evidence : [observation |-> item, day |-> 1] \in views[replica].contributions
ExportUsesCheckedSnapshot ==
    \A replica \in Replicas : published[replica] # {} => published[replica] = prepared[replica]
NoUnresolvedExport ==
    \A replica \in Replicas : \A snapshot \in published[replica] : snapshot.issues = {}

LateSelectedObservationNotReached ==
    ~(sawGap[1] /\ controls[1] = {"dayA"} /\
      [device |-> "A", instant |-> 0] \in received[1] /\
      views[1].segments[0].selected = {[device |-> "A", instant |-> 0]})
LateIgnoredObservationNotReached ==
    ~(sawIgnoreBeforeA[1] /\ controls[1] = {"ignoreA"} /\
      At(received[1], 0) = [device : Devices, instant : {0}] /\
      views[1].segments[0].selected = {[device |-> "B", instant |-> 0]})
CompatibleAutomaticDifferenceNotReached ==
    ~(ReplicaCount = 2 /\ received[1] = received[2] /\ controls[1] = {} /\ controls[2] = {} /\
      versions[1] # versions[2] /\ views[1].segments[0].selected # views[2].segments[0].selected)
CompleteExportThenConflictNotReached ==
    ~(prepared[1] # {} /\ views[1].issues # {})
PartialDayNotReached ==
    ~(views[1].issues # {} /\ views[1].contributions # {} /\ queries[1] = {1})

====
