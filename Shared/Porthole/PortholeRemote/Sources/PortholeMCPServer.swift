import Foundation
import PortholeCore

/// A small stdio MCP bridge exposes discovery and invocation through one already paired client.
public actor PortholeMCPServer {
    private struct Request: Decodable {
        let jsonrpc: String
        let id: PortholeValue?
        let method: String
        let params: PortholeValue?
    }

    private enum State { case new, initializing, ready }
    private let client: PortholeRemoteClient
    private var state: State = .new

    public init(client: PortholeRemoteClient) {
        self.client = client
    }

    /// Returns nil for notifications. Credentials and enrollment are absent from this protocol.
    public func respond(to data: Data) async throws -> Data? {
        guard data.count <= PortholeRemoteFraming.maximumBytes else { return try encode(error(
            id: .null,
            code: -32600,
            message: "Request exceeds the size limit.",
        )) }
        let request: Request
        do { request = try JSONDecoder().decode(Request.self, from: data) }
        catch { return try encode(self.error(
            id: .null,
            code: -32700,
            message: "Invalid JSON-RPC request.",
        )) }
        guard request.jsonrpc == "2.0" else { return try encode(error(
            id: request.id ?? .null,
            code: -32600,
            message: "Expected JSON-RPC 2.0.",
        )) }
        guard let requestID = request.id else {
            if request.method == "notifications/initialized",
               state == .initializing { state = .ready }
            return nil
        }
        switch requestID {
            case .string, .integer, .unsignedInteger: break
            case .null, .bool, .number, .array, .object: return try encode(error(
                    id: .null,
                    code: -32600,
                    message: "Request ID must be a string or integer.",
                ))
        }
        let result: PortholeValue
        switch request.method {
            case "initialize":
                guard state == .new else { return try encode(error(
                    id: requestID,
                    code: -32600,
                    message: "This session is already initialized.",
                )) }
                state = .initializing
                result = .object([
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                    "serverInfo": .object(["name": .string("Porthole"), "version": .string("1")]),
                    "instructions": .string(
                        "Inspect the application and its current scopes, list capabilities, then invoke them. Live changes require approval on the device. Reuse the exact invocation only after approval. A transport failure never implies rollback.",
                    ),
                ])
            case "ping": result = .object([:])
            case "tools/list":
                guard state == .ready else { return try encode(error(
                    id: requestID,
                    code: -32002,
                    message: "Initialize this session first.",
                )) }
                result = .object(["tools": .array(Self.tools)])
            case "tools/call":
                guard state == .ready else { return try encode(error(
                    id: requestID,
                    code: -32002,
                    message: "Initialize this session first.",
                )) }
                guard case let .object(parameters) = request.params,
                      case let .string(name) = parameters["name"]
                else {
                    return try encode(error(
                        id: requestID,
                        code: -32602,
                        message: "A tool name is required.",
                    ))
                }
                guard ["porthole_application", "porthole_capabilities", "porthole_invoke"]
                    .contains(name)
                else {
                    return try encode(error(
                        id: requestID,
                        code: -32602,
                        message: "Unknown Porthole tool.",
                    ))
                }
                result = await call(name: name, arguments: parameters["arguments"] ?? .object([:]))
            default: return try encode(error(
                    id: requestID,
                    code: -32601,
                    message: "Method is not supported.",
                ))
        }
        return try encode(.object(["jsonrpc": .string("2.0"), "id": requestID, "result": result]))
    }

    private func call(name: String, arguments: PortholeValue) async -> PortholeValue {
        do {
            let value: PortholeValue
            switch name {
                case "porthole_application": value = try await json(client.application())
                case "porthole_capabilities":
                    guard case let .object(fields) = arguments,
                          let scope = fields["scope"],
                          case let .integer(offset) = fields["offset"],
                          case let .integer(limit) = fields["limit"],
                          let pageOffset = Int(exactly: offset),
                          let pageLimit = Int(exactly: limit)
                    else { throw PortholeRemoteError.invalidMessage }
                    let token = try JSONDecoder().decode(
                        PortholeScopeToken.self,
                        from: JSONEncoder().encode(scope),
                    )
                    value = try await json(client.capabilityPage(
                        in: token,
                        offset: pageOffset,
                        limit: pageLimit,
                    ))
                case "porthole_invoke":
                    guard case let .object(fields) = arguments,
                          let invocation = fields["invocation"]
                    else { throw PortholeRemoteError.invalidMessage }
                    let call = try JSONDecoder().decode(
                        PortholeInvocation.self,
                        from: JSONEncoder().encode(invocation),
                    )
                    value = try await client.invoke(call)
                default: throw PortholeRemoteError.invalidMessage
            }
            return try toolResult(value, isError: false)
        } catch let PortholeError.approvalRequired(proposal) {
            do { return try toolResult(
                .object(["status": .string("approval_required"), "proposal": json(proposal)]),
                isError: false,
            ) } catch { return failure(message: error.localizedDescription) }
        } catch { return failure(message: error.localizedDescription) }
    }

    private func toolResult(_ value: PortholeValue, isError: Bool) throws -> PortholeValue {
        let text = try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError),
        ])
    }

    private func failure(message: String) -> PortholeValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
            "isError": .bool(true),
        ])
    }

    private func json(_ value: some Encodable) throws -> PortholeValue {
        try JSONDecoder().decode(
            PortholeValue.self,
            from: JSONEncoder().encode(value),
        )
    }

    private func encode(_ value: PortholeValue) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func error(id: PortholeValue, code: Int64, message: String) -> PortholeValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .integer(code), "message": .string(message)]),
        ])
    }

    private static let tools: [PortholeValue] = [
        tool(
            name: "porthole_application",
            description: "Read the paired application's current scope generations.",
            properties: [:],
            required: [],
            readOnly: true,
        ),
        tool(
            name: "porthole_capabilities",
            description: "Inspect a bounded page of callable APIs, effect classifications, parameter schemas, source locations and unsupported declarations in one current scope. Returns offset, total and items.",
            properties: [
                "scope": .object(["type": .string("object")]),
                "offset": .object(["type": .string("integer"), "minimum": .integer(0)]),
                "limit": .object([
                    "type": .string("integer"),
                    "minimum": .integer(1),
                    "maximum": .integer(200),
                ]),
            ],
            required: ["scope", "offset", "limit"],
            readOnly: true,
        ),
        tool(
            name: "porthole_invoke",
            description: "Invoke one capability with its complete invocation: id UUID, scope, capabilityID, optional receiver and arguments. Source, screenshots, files, logs and persistence use the advertised capabilities. Live changes return a proposal for device approval.",
            properties: ["invocation": .object(["type": .string("object")])],
            required: ["invocation"],
            readOnly: false,
        ),
    ]

    private static func tool(
        name: String,
        description: String,
        properties: [String: PortholeValue],
        required: [String],
        readOnly: Bool,
    ) -> PortholeValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(PortholeValue.string)),
                "additionalProperties": .bool(false),
            ]),
            "annotations": .object([
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": .bool(!readOnly),
                "idempotentHint": .bool(readOnly),
                "openWorldHint": .bool(!readOnly),
            ]),
        ])
    }
}
