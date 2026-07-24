import Foundation
import PortholeCore

/// The outcome of an MCP tool call, independent of the MCP SDK types so it can
/// be unit-tested. The server maps it to `CallTool.Result`.
public enum MCPCallResult: Sendable, Equatable {
    case json(PortholeValue)
    case image(Data)
    case failure(String)
}

/// Dispatches an MCP tool call to a `PortholeSessionProviding`. Holds the
/// manifest (for `porthole_overview`) and the tool-name → target map derived
/// from `MCPToolBuilder`. Pure of MCP SDK types.
public struct PortholeMCPDispatcher: Sendable {
    private let session: any PortholeSessionProviding
    private let manifests: [ConnectorManifest]
    private let targets: [String: MCPToolTarget]

    public init(session: any PortholeSessionProviding, manifests: [ConnectorManifest]) {
        self.session = session
        self.manifests = manifests
        targets = Dictionary(
            MCPToolBuilder.plan(from: manifests).map { ($0.name, $0.target) },
            uniquingKeysWith: { first, _ in first },
        )
    }

    public func plannedTools() -> [PlannedTool] {
        MCPToolBuilder.plan(from: manifests)
    }

    public func call(name: String, arguments: PortholeValue) async -> MCPCallResult {
        guard let target = targets[name] else {
            return .failure("Unknown tool `\(name)`.")
        }
        switch target {
            case .overview:
                return .json(MCPValueBridge.overview(manifests))
            case let .action(ref):
                return await invoke(ref, arguments: arguments)
            case let .query(ref):
                return await runQuery(ref, arguments: arguments)
            case let .tail(ref):
                return await runTail(ref, arguments: arguments)
        }
    }

    private func invoke(_ ref: PortholeActionRef, arguments: PortholeValue) async -> MCPCallResult {
        do {
            let result = try await session.invoke(ref, parameters: arguments)
            if let png = extractPNG(result) {
                return .image(png)
            }
            return .json(result)
        } catch {
            return .failure(String(describing: error))
        }
    }

    private func runQuery(
        _ ref: PortholeDataSourceRef,
        arguments: PortholeValue,
    ) async -> MCPCallResult {
        var filters = arguments.objectValue ?? [:]
        let limit = filters.removeValue(forKey: "limit")?.intValue.map { Int($0) }
        let cursor = filters.removeValue(forKey: "cursor")?.stringValue
        do {
            let page = try await session.query(
                ref,
                PortholeQuery(filters: .object(filters), limit: limit, cursor: cursor),
            )
            return .json(pageValue(page))
        } catch {
            return .failure(String(describing: error))
        }
    }

    private func runTail(
        _ ref: PortholeDataSourceRef,
        arguments: PortholeValue,
    ) async -> MCPCallResult {
        var filters = arguments.objectValue ?? [:]
        let duration = min(
            Int(filters.removeValue(forKey: "durationSeconds")?.intValue ?? 5),
            MCPToolBuilder.maxTailDurationSeconds,
        )
        let maxEvents = min(
            Int(filters.removeValue(forKey: "maxEvents")?.intValue ?? 100),
            MCPToolBuilder.maxTailEvents,
        )
        do {
            let stream = try await session.subscribe(ref)
            let events = await collect(
                stream,
                forSeconds: max(1, duration),
                maxEvents: max(1, maxEvents),
            )
            return .json(.array(events))
        } catch {
            return .failure(String(describing: error))
        }
    }

    private func collect(
        _ stream: AsyncThrowingStream<PortholeValue, Error>,
        forSeconds seconds: Int,
        maxEvents: Int,
    ) async -> [PortholeValue] {
        let box = EventBox(maxEvents: maxEvents)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await value in stream {
                        if await box.append(value) { break }
                    }
                } catch {}
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
            }
            await group.next()
            group.cancelAll()
        }
        return await box.events
    }

    private func pageValue(_ page: PortholePage) -> PortholeValue {
        var object: [String: PortholeValue] = ["rows": .array(page.rows)]
        if let cursor = page.nextCursor { object["nextCursor"] = .string(cursor) }
        if let total = page.totalCount { object["totalCount"] = .int(Int64(total)) }
        return .object(object)
    }

    /// A bare PNG data value, or the first PNG data member of an object result.
    private func extractPNG(_ value: PortholeValue) -> Data? {
        if case let .data(data) = value, MCPValueBridge.isPNG(data) { return data }
        if case let .object(object) = value {
            for member in object.values {
                if case let .data(data) = member, MCPValueBridge.isPNG(data) { return data }
            }
        }
        return nil
    }
}

/// Bounds tail collection to a max event count.
private actor EventBox {
    private let maxEvents: Int
    private(set) var events: [PortholeValue] = []

    init(maxEvents: Int) {
        self.maxEvents = maxEvents
    }

    /// Appends and returns whether the cap is reached.
    func append(_ value: PortholeValue) -> Bool {
        events.append(value)
        return events.count >= maxEvents
    }
}
