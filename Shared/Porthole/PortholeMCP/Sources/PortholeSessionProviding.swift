import Foundation
import PortholeClientKit
import PortholeCore

/// The slice of a live session the MCP server needs. A protocol so the tool
/// builder and dispatch can be tested against a scripted fake without a device.
public protocol PortholeSessionProviding: Sendable {
    func manifest() async throws -> [ConnectorManifest]
    func invoke(_ ref: PortholeActionRef, parameters: PortholeValue) async throws -> PortholeValue
    func query(_ ref: PortholeDataSourceRef, _ query: PortholeQuery) async throws -> PortholePage
    func subscribe(_ ref: PortholeDataSourceRef) async throws
        -> AsyncThrowingStream<PortholeValue, Error>
}

extension PortholeSession: PortholeSessionProviding {}
