/// Defines a stable logging scope and generates typed event methods.
@attached(member, names: arbitrary)
@attached(extension, conformances: LogScopeDefinition)
public macro LogScope(_ id: String) = #externalMacro(
    module: "PeriscopeMacros",
    type: "LogScopeMacro",
)

/// Defines a stable, classified event nested directly in a ``LogScope`` namespace.
@attached(member, names: arbitrary)
@attached(extension, conformances: LogEvent)
public macro LogEvent(
    _ id: String,
    level: LogLevel? = nil,
    message: String? = nil,
    version: Int = 1,
) = #externalMacro(
    module: "PeriscopeMacros",
    type: "LogEventMacro",
)
