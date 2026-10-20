/// Entry point compiled beside native app/extension views, without their app entry point.
@main
@MainActor
enum NativeLayoutAudit {
    static func main() throws {
        try ViewLayoutAuditRunner.run(records: _ViewLayoutAuditRegistry.records())
    }
}
