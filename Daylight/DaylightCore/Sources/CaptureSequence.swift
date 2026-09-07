import Foundation

/// Durable sequence state. Slot transitions are written before invoking camera or Photos APIs.
public struct CaptureSequence: Codable, Equatable, Sendable, Identifiable {
    public var id: SolarEvent.ID {
        event.id
    }

    public let event: SolarEvent
    public var settings: CaptureSettings
    public var slots: [Slot]
    public var selection: Selection = .pending
    public var deliveries: [PublishingDelivery] = []

    public struct Slot: Codable, Equatable, Sendable, Identifiable {
        public struct ID: Codable, Hashable, Sendable {
            public let rawValue: UUID
            public init(rawValue: UUID) {
                self.rawValue = rawValue
            }
        }

        public let id: ID
        public let scheduledAt: Date
        public var state: State
        public enum State: Codable, Equatable, Sendable {
            case pending, missed, capturing
            case captured(CapturedImage)
            case failed(String)
        }
    }

    public enum Selection: Codable, Equatable, Sendable {
        case pending, selected(Slot.ID), failed(String)
    }

    public var end: Date {
        event.date.addingTimeInterval(Double(settingsWindow.minutesAfter) * 60)
    }

    public var settingsWindow: CaptureSettings.Window {
        switch event.id.kind { case .sunrise: settings.sunrise; case .sunset: settings.sunset }
    }

    public var images: [CapturedImage] {
        slots.compactMap { if case let .captured(image) = $0.state { image } else { nil } }
    }

    public init(event: SolarEvent, settings: CaptureSettings) {
        self.event = event
        self.settings = settings
        let window = event.id.kind == .sunrise ? settings.sunrise : settings.sunset
        slots = stride(
            from: -window.minutesBefore,
            through: window.minutesAfter,
            by: max(1, window.intervalMinutes),
        ).map {
            Slot(
                id: .init(rawValue: UUID()),
                scheduledAt: event.date.addingTimeInterval(Double($0) * 60),
                state: .pending,
            )
        }
    }
}
