import BumperBowlingCore

let repositoryProjectRules = RuleSet {
    Rules.singleNominalSpelling(
        suffix: "Log",
        owner: loggingScope,
        id: "repository.logging_type_ownership",
    )
}

private let loggingScope = RuleScope
    .under("Where/RegionKit/Sources/Logging")
    .union(.under("Where/Where/Sources/Logging"))
    .union(.under("Where/WhereCore/Sources/Logging"))
    .union(.under("Where/WhereUI/Sources/Logging"))
    .union(.under("Where/WhereIntents/Sources/Logging"))
    .union(.under("Where/WhereWidgets/Sources/Logging"))
    .union(.under("Where/WhereShareExtension/Sources/Logging"))
    .union(.under("Throw/Throw/Sources/Logging"))
    .union(.under("Throw/ThrowCore/Sources/Logging"))
    .union(.under("Throw/ThrowUI/Sources/Logging"))
