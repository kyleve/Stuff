@testable import PeriscopeMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

private let macros: [String: any Macro.Type] = [
    "LogEvent": LogEventMacro.self,
    "LogScope": LogScopeMacro.self,
]

@Test
func expandsClassifiedEventAndLogMethod() {
    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("counted", level: .notice, message: "Counted")
            struct Counted {
                @LogField("count", exposure: .shareable, kind: .count)
                var count: Int
            }
        }
        """,
        expandedSource: """
        enum SampleLog {
            struct Counted {
                @LogField("count", exposure: .shareable, kind: .count)
                var count: Int

                static let eventName = SampleLog.scopeName + ".counted"

                static let eventVersion = 1

                private enum CodingKeys: String, CodingKey {
                        case count = "count"
                }

                init(
                        count: ClassifiedLogInput<LogFieldPolicy.Shared, LogFieldPolicy.Count, Int>
                ) {
                        self._count = LogField(wrappedValue: count.value, "count", exposure: .shareable, kind: .count)
                }

                var classifiedFields: [ClassifiedLogField] {
                    var fields: [ClassifiedLogField] = []
                        fields.append(.shareable(key: LogFieldKey("count"), kind: .count, value: .int(count)))
                    return fields
                }

                var level: LogLevel {
                    .notice
                }

                var message: String {
                    "Counted"
                }

                var externalID: String? {
                    nil
                }

                static var isProtectedFromDropping: Bool {
                    false
                }
            }

            static let scopeName = "Sample"

            struct LogMethods {
                fileprivate let log: Log<SampleLog>

                var counted: CountedLogMethod {
                    CountedLogMethod(log: log)
                }
            }

            struct CountedLogMethod {
                fileprivate let log: Log<SampleLog>

                func callAsFunction(
                    count: ClassifiedLogInput<LogFieldPolicy.Shared, LogFieldPolicy.Count, Int>,
                    attachments: [LogAttachment] = [],
                    function: StaticString = #function,
                    fileID: StaticString = #fileID
                ) {
                    log.record(
                        SampleLog.Counted(
                            count: count
                        ),
                        attachments: attachments,
                        function: function,
                        fileID: fileID
                    )
                }
            }

            static func makeLogMethods(_ log: Log<SampleLog>) -> LogMethods {
                LogMethods(log: log)
            }
        }

        extension SampleLog.Counted: LogEvent {
        }

        extension SampleLog: LogScopeDefinition {
        }
        """,
        macros: macros,
    )
}

@Test
func eventRequiresStruct() {
    assertMacroExpansion(
        "@LogEvent(\"value\", message: \"Value\") enum Value {}",
        expandedSource: "enum Value {}",
        diagnostics: [
            DiagnosticSpec(message: "@LogEvent requires a struct", line: 1, column: 1),
        ],
        macros: macros,
    )
}

@Test
func eventRequiresScope() {
    assertMacroExpansion(
        "@LogEvent(\"value\", message: \"Value\") struct Value {}",
        expandedSource: "struct Value {}",
        diagnostics: [
            DiagnosticSpec(
                message: "@LogEvent must be nested directly in an @LogScope enum",
                line: 1,
                column: 1,
            ),
        ],
        macros: macros,
    )
}

@Test
func eventRequiresAMessage() {
    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("event")
            struct Event {}
        }
        """,
        expandedSource: """
        @LogScope("Sample")
        enum SampleLog {
            struct Event {}
        }

        extension SampleLog.Event: LogEvent {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "an event requires a static or instance message",
                line: 3,
                column: 5,
            ),
        ],
        macros: ["LogEvent": LogEventMacro.self],
    )
}

@Test
func eventRejectsInvalidIdentifiersAndVersions() {
    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("", message: "Event")
            struct Event {}
        }
        """,
        expandedSource: """
        @LogScope("Sample")
        enum SampleLog {
            struct Event {}
        }

        extension SampleLog.Event: LogEvent {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "@LogEvent requires a nonempty string-literal event ID",
                line: 3,
                column: 5,
            ),
        ],
        macros: ["LogEvent": LogEventMacro.self],
    )

    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("event", message: "Event", version: 0)
            struct Event {}
        }
        """,
        expandedSource: """
        @LogScope("Sample")
        enum SampleLog {
            struct Event {}
        }

        extension SampleLog.Event: LogEvent {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "version must be a positive integer literal",
                line: 3,
                column: 42,
            ),
        ],
        macros: ["LogEvent": LogEventMacro.self],
    )
}

@Test
func eventRejectsUnclassifiedAndInvalidShareableFields() {
    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("event", message: "Event")
            struct Event {
                var count: Int
            }
        }
        """,
        expandedSource: """
        @LogScope("Sample")
        enum SampleLog {
            struct Event {
                var count: Int
            }
        }

        extension SampleLog.Event: LogEvent {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "stored event properties require a complete @LogField classification",
                line: 5,
                column: 9,
            ),
        ],
        macros: ["LogEvent": LogEventMacro.self],
    )

    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("event", message: "Event")
            struct Event {
                @LogField("value", exposure: .shareable, kind: .identifier)
                var value: String
            }
        }
        """,
        expandedSource: """
        @LogScope("Sample")
        enum SampleLog {
            struct Event {
                @LogField("value", exposure: .shareable, kind: .identifier)
                var value: String
            }
        }

        extension SampleLog.Event: LogEvent {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "field kind '.identifier' cannot be shareable",
                line: 5,
                column: 9,
            ),
            DiagnosticSpec(
                message: "shareable .identifier requires its classified Swift value type",
                line: 5,
                column: 9,
            ),
        ],
        macros: ["LogEvent": LogEventMacro.self],
    )
}

@Test
func scopeRejectsEventMethodNamesThatCollideWithGeneratedMembers() {
    assertMacroExpansion(
        """
        @LogScope("Sample")
        enum SampleLog {
            @LogEvent("log", message: "Log")
            struct Log {}
        }
        """,
        expandedSource: """
        enum SampleLog {
            @LogEvent("log", message: "Log")
            struct Log {}

            static let scopeName = "Sample"
        }

        extension SampleLog: LogScopeDefinition {
        }
        """,
        diagnostics: [
            DiagnosticSpec(
                message: "generated log method 'log' conflicts with a reserved LogMethods member",
                line: 3,
                column: 5,
            ),
        ],
        macros: ["LogScope": LogScopeMacro.self],
    )
}
