import PeriscopeCore

@LogScope("HistoryRegionAttribution")
enum HistoryRegionAttributionLog {
    enum SpanName: Hashable {
        case loadCatalog
    }
}
