import Foundation
import PortholeCore
@testable import PortholeMCP

/// A scripted `PortholeSessionProviding` for exercising the tool builder and
/// dispatcher without a device.
struct FakeSession: PortholeSessionProviding {
    var manifests: [ConnectorManifest]
    var onInvoke: @Sendable (PortholeActionRef, PortholeValue) async throws
        -> PortholeValue = { _, _ in .null }
    var onQuery: @Sendable (PortholeDataSourceRef, PortholeQuery) async throws
        -> PortholePage = { _, _ in PortholePage(rows: []) }
    var onSubscribe: @Sendable (PortholeDataSourceRef)
        -> AsyncThrowingStream<PortholeValue, Error> = { _ in
            AsyncThrowingStream { $0.finish() }
        }

    func manifest() async throws -> [ConnectorManifest] {
        manifests
    }

    func invoke(_ ref: PortholeActionRef, parameters: PortholeValue) async throws -> PortholeValue {
        try await onInvoke(ref, parameters)
    }

    func query(_ ref: PortholeDataSourceRef, _ query: PortholeQuery) async throws -> PortholePage {
        try await onQuery(ref, query)
    }

    func subscribe(_ ref: PortholeDataSourceRef) async throws
        -> AsyncThrowingStream<PortholeValue, Error>
    {
        onSubscribe(ref)
    }
}

/// A one-connector manifest fixture: `test` with an `echo` action and a
/// subscribable `ticks` source plus a paged `rows` source.
func fixtureManifests() -> [ConnectorManifest] {
    [
        ConnectorManifest(
            connector: PortholeConnectorDescriptor(
                id: "test",
                title: "Test",
                summary: "Fixture.",
                version: 1,
            ),
            actions: [
                PortholeActionDescriptor(
                    id: "echo",
                    title: "Echo",
                    summary: "Echoes a value.",
                    parameters: .object(["value": .integer()], required: ["value"]),
                    isDestructive: false,
                ),
                PortholeActionDescriptor(
                    id: "wipe",
                    title: "Wipe",
                    summary: "Deletes stuff.",
                    parameters: .object([:]),
                    isDestructive: true,
                ),
            ],
            dataSources: [
                PortholeDataSourceDescriptor(
                    id: "rows",
                    title: "Rows",
                    summary: "Paged rows.",
                    rowSchema: .object(["n": .integer()]),
                    filters: .object(["count": .integer()]),
                    supportsSubscription: false,
                ),
                PortholeDataSourceDescriptor(
                    id: "ticks",
                    title: "Ticks",
                    summary: "Live counter.",
                    rowSchema: .object(["tick": .integer()]),
                    filters: .object([:]),
                    supportsSubscription: true,
                ),
            ],
        ),
    ]
}

/// A minimal valid PNG (signature + IHDR-ish bytes) for image-detection tests.
func pngData() -> Data {
    Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01, 0x02, 0x03])
}
