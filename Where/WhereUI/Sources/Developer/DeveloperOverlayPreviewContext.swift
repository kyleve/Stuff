#if DEBUG
    import PeriscopeTools

    /// Fully attached in-memory dependencies for developer-overlay previews and
    /// snapshots.
    @MainActor
    struct DeveloperOverlayPreviewContext {
        let model: WhereModel
        let session: WhereSession
        let inspector: PeriscopeInspector
        let overlayModel: DeveloperOverlayModel
    }
#endif
