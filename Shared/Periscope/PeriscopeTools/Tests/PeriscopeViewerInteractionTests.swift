import AccessibilitySnapshotParser
import PeriscopeCore
import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct PeriscopeViewerInteractionTests {
    @Test func exportPresentsTheStoredEventAsNDJSON() async throws {
        let (store, _, _, scope) = try await makeSeededStore()
        let message = "Export this stored event"
        await store.write([makeRecord(message, date: date(1), scopes: [scope.id])])
        let host = UIHostingController(rootView: NavigationStack { PeriscopeViewer(store: store) })
        try await show(host) { controller in
            let window = try #require(controller.view.window)
            window.layer.speed = 1
            try await waitForHostedState("Display stored event in the log list", in: window) {
                contains(
                    message,
                    in: window,
                )
            }
            try await activateHostedButton("Export", in: window) { $0 == "Export" }
            try await waitForHostedState(
                "Present the NDJSON sheet and exported event",
                in: window,
            ) {
                guard contains("NDJSON Export", in: window) else { return false }
                return hostedAccessibilityObjects(in: window).contains { object in
                    [object.accessibilityValue, object.accessibilityLabel].compactMap(\.self)
                        .contains { text in
                            text.split(whereSeparator: \.isNewline).contains { line in
                                guard let record = try? JSONSerialization
                                    .jsonObject(with: Data(line.utf8))
                                    as? [String: Any] else { return false }
                                return record["message"] as? String == message &&
                                    record["event"] as? String == "message.message"
                            }
                        }
                }
            }
        }
    }

    private func contains(_ text: String, in window: UIWindow) -> Bool {
        hostedAccessibilityObjects(in: window).contains { object in
            object.accessibilityLabel?.contains(text) == true && object.accessibilityFrame
                .intersects(window.bounds)
        }
    }
}
