#if DEBUG
    import Inspector
    import PeriscopeTools

    /// Fully attached in-memory dependencies for developer-overlay previews and
    /// snapshots.
    @MainActor
    struct DeveloperOverlayPreviewContext {
        let model: WhereModel
        let modeController: InspectorModeController
        let inspector: PeriscopeInspector
        let overlayModel: DeveloperOverlayModel
    }
#endif
