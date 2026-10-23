import PeriscopeCore

@LogScope("ElsewhereResolver")
enum ElsewhereResolverLog {
    enum SpanName: Hashable {
        case resolve
        case loadCatalog
    }
}
