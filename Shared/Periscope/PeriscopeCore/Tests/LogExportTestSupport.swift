import PeriscopeCore

extension LogExportControl {
    static let customerDiagnostics = Self("example.customer-diagnostics")
    static let futureControl = Self("example.future-control")
}

@LogScope("ExportTest")
enum LogExportTestLog {
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
