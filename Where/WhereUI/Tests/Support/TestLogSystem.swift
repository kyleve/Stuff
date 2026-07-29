import PeriscopeCore

extension Periscope {
    /// A logging system private to one test: no sinks, and nothing shared with
    /// the process-wide pipeline.
    ///
    /// Every `WhereModel` a test builds takes one of these. Handing it
    /// `Periscope.shared` instead would leave whatever sinks its scopes attach
    /// (a demo world's in-memory log store, say) registered on the pipeline for
    /// the rest of the test host's life, and would put a test's records in the
    /// same stream as everyone else's.
    static func isolated() -> Periscope {
        Periscope(configuration: Configuration(), sinks: [])
    }
}
