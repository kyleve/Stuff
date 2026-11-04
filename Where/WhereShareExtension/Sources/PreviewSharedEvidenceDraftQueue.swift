#if DEBUG
    import WhereCore

    /// Keeps the compose preview entirely in memory and outside the App Group.
    actor PreviewSharedEvidenceDraftQueue: SharedEvidenceDraftQueuing {
        private var drafts: [SharedEvidenceDraft.ID: SharedEvidenceDraft] = [:]
        func enqueue(_ draft: SharedEvidenceDraft) {
            drafts[draft.id] = draft
        }

        func pendingDraftIDs() -> [SharedEvidenceDraft.ID] {
            Array(drafts.keys)
        }

        func draft(for draftID: SharedEvidenceDraft.ID) -> SharedEvidenceDraft? {
            drafts[draftID]
        }

        func acknowledge(_ draftID: SharedEvidenceDraft.ID) {
            drafts.removeValue(forKey: draftID)
        }
    }
#endif
