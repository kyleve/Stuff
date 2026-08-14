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
