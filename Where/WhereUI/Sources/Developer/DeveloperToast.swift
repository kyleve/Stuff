#if DEBUG
    import Observation
    import PeriscopeCore
    import PeriscopeTools
    import SFSafeSymbols
    import SwiftUI

    /// The DEBUG-only in-app toast surface for high-severity log records.
    ///
    /// A `PeriscopeAlerter` (started at `RootView`, threshold `.warning`) feeds
    /// `DeveloperToastAlertHandler`, which appends to this center; the
    /// `DeveloperToastOverlay` mounted above the app renders the transient
    /// banners. This keeps warning/error logs visible while developing without
    /// routing through the notification center (which would collide with the
    /// app's real reminders). Compiled out of release entirely.
    @MainActor
    @Observable
    final class DeveloperToastCenter {
        /// One transient banner for a logged record at or above the alert
        /// threshold.
        struct Toast: Identifiable, Equatable {
            let id = UUID()
            let level: LogLevel
            let title: String
            let message: String
        }

        private(set) var toasts: [Toast] = []

        /// How long a toast stays on screen before it auto-dismisses.
        private let lifetime: Duration

        /// The most banners shown at once; older ones drop so an error storm
        /// can't fill the screen.
        private let maximumVisible = 3

        init(lifetime: Duration = .seconds(4)) {
            self.lifetime = lifetime
        }

        func show(_ toast: Toast) {
            toasts.append(toast)
            if toasts.count > maximumVisible {
                toasts.removeFirst(toasts.count - maximumVisible)
            }
            Task {
                try? await Task.sleep(for: lifetime)
                dismiss(toast.id)
            }
        }

        func dismiss(_ id: Toast.ID) {
            toasts.removeAll { $0.id == id }
        }
    }

    /// Routes alerted records into a `DeveloperToastCenter`. `@MainActor` per the
    /// `PeriscopeAlertHandler` contract; it never logs at or above the alerter's
    /// threshold, so it can't alert itself in a loop.
    @MainActor
    struct DeveloperToastAlertHandler: PeriscopeAlertHandler {
        let center: DeveloperToastCenter

        func handle(_ record: LogRecord) {
            center.show(DeveloperToastCenter.Toast(
                level: record.level,
                title: record.eventName,
                message: record.message,
            ))
        }
    }

    /// Renders a `DeveloperToastCenter`'s banners stacked from the top edge.
    /// Non-interactive except for a tap-to-dismiss on each banner, so the app
    /// behind stays usable.
    struct DeveloperToastOverlay: View {
        let center: DeveloperToastCenter

        var body: some View {
            VStack(spacing: 8) {
                ForEach(center.toasts) { toast in
                    DeveloperToastBanner(toast: toast) { center.dismiss(toast.id) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.snappy, value: center.toasts)
            .allowsHitTesting(!center.toasts.isEmpty)
        }
    }

    private struct DeveloperToastBanner: View {
        let toast: DeveloperToastCenter.Toast
        let onDismiss: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemSymbol: symbol)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.caption.weight(.semibold))
                    Text(toast.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.6), lineWidth: 1),
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }

        private var tint: Color {
            toast.level >= .error ? .red : .orange
        }

        private var symbol: SFSymbol {
            toast.level >= .error
                ? .exclamationmarkOctagonFill
                : .exclamationmarkTriangleFill
        }
    }

    #Preview {
        let center = DeveloperToastCenter(lifetime: .seconds(3600))
        center.show(DeveloperToastCenter.Toast(
            level: .warning,
            title: "Location sample delayed",
            message: "The background location stream has not produced a sample recently.",
        ))
        center.show(DeveloperToastCenter.Toast(
            level: .error,
            title: "Store write failed",
            message: "The latest presence sample could not be persisted.",
        ))
        return DeveloperToastOverlay(center: center)
    }
#endif
