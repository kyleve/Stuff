import Foundation
import Observation
import WhereSurface

/// Keeps the helper's last successfully decoded glance payload.
///
/// A failed advisory refresh never replaces loaded content with an empty state;
/// the popover continues to show that snapshot with its original generation
/// date and makes the refresh failure visible.
@MainActor
@Observable
final class WhereMenuBarModel {
    enum UnavailableReason: Equatable {
        case notPublished
        case unreadable
        case appGroupUnavailable
    }

    enum State: Equatable {
        case unavailable(UnavailableReason)
        case loaded(
            generatedAt: Date,
            snapshot: WhereSurfaceSnapshot,
            refreshFailed: Bool,
        )
    }

    private let reader: (any WhereSurfaceReading)?
    private(set) var state: State

    init(reader: any WhereSurfaceReading) {
        self.reader = reader
        state = .unavailable(.notPublished)
        refresh()
    }

    /// Builds an honest unavailable model when the App Group entitlement
    /// cannot be resolved. That configuration cannot recover during this
    /// process lifetime, so there is no reader to retry.
    init(appGroupUnavailable _: WhereSurfaceStore.AppGroupUnavailableError) {
        reader = nil
        state = .unavailable(.appGroupUnavailable)
    }

    func refresh() {
        guard let reader else { return }
        do {
            guard let document = try reader.read() else {
                handleUnavailable(.notPublished)
                return
            }
            guard
                let generatedAt = document.generatedAt,
                let snapshot = document.surface
            else {
                handleUnavailable(.notPublished)
                return
            }
            state = .loaded(
                generatedAt: generatedAt,
                snapshot: snapshot,
                refreshFailed: false,
            )
        } catch {
            handleUnavailable(.unreadable)
        }
    }

    private func handleUnavailable(_ reason: UnavailableReason) {
        switch state {
            case let .loaded(generatedAt, snapshot, _):
                state = .loaded(
                    generatedAt: generatedAt,
                    snapshot: snapshot,
                    refreshFailed: true,
                )
            case .unavailable:
                state = .unavailable(reason)
        }
    }
}
