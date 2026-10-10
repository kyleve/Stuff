import PeriscopeCore

extension LogExportControl {
    static let customerDiagnostics = Self("example.customer-diagnostics")
    static let futureControl = Self("example.future-control")
}

enum LogExportTestValues {
    /// A consumer type whose name must not opt it into framework error permissions.
    struct LogError: Codable {
        let email: String
    }
}

@LogScope("ExportTest")
enum LogExportTestLog {
    typealias LogError = LogExportTestValues.LogError
    typealias ErrorAlias = PeriscopeCore.LogError
    typealias OptionalErrorAlias = PeriscopeCore.LogError?

    @LogEvent("error-defaults", message: "Error defaults")
    struct ErrorDefaults {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var shadowed: LogError
        @LogField(exposure: .restricted, kind: .errorDetails)
        var optionalShadowed: LogError?
        @LogField(exposure: .restricted, kind: .errorDetails)
        var qualified: PeriscopeCore.LogError
        @LogField(exposure: .restricted, kind: .errorDetails)
        var optionalQualified: PeriscopeCore.LogError?
        @LogField(exposure: .restricted, kind: .errorDetails)
        var aliased: ErrorAlias
        @LogField(exposure: .restricted, kind: .errorDetails)
        var optionalAliased: OptionalErrorAlias
        @LogField(exposure: .restricted, kind: .errorDetails, export: .never)
        var denied: ErrorAlias
    }

    @LogEvent("child", message: "Child")
    struct Child {
        @LogField(exposure: .restricted, kind: .arbitraryText, export: .never)
        var secret: JSONValue
        @LogField(
            exposure: .restricted,
            kind: .arbitraryText,
            export: .diagnostic(requiring: [.customerDiagnostics]),
        )
        var detail: String
        @LogField(exposure: .shareable, kind: .count)
        var count: Int
    }

    @LogEvent("parent", message: "Parent")
    struct Parent {
        @LogField(
            exposure: .restricted,
            kind: .domainValue,
            export: .diagnostic(requiring: [.location]),
        )
        var children: [String: [Child?]]
    }

    @LogEvent("restricted", message: "Restricted")
    struct Restricted {
        @LogField(exposure: .restricted, kind: .count, export: .baseline(requiring: []))
        var count: Int
    }
}
