import PortholeCore

/// Finds typed argument handles before a native call suspends so their leases cannot expire
/// mid-call.
enum PortholeObjectReferences {
    static func inArguments(of invocation: PortholeInvocation) throws -> [PortholeObjectReference] {
        var references = invocation.receiver.map { [$0] } ?? []
        var pending = [invocation.arguments]
        var visited = 0
        while let value = pending.popLast() {
            visited += 1
            guard visited <= 100_000
            else {
                throw PortholeError
                    .invalidArguments("Too many argument values to validate object lifetimes")
            }
            switch value {
                case let .object(fields):
                    if let reference = fields["$reference"] {
                        try references.append(reference.decode(PortholeObjectReference.self))
                    } else if fields["scope"] != nil, fields["id"] != nil,
                              fields["typeName"] != nil
                    {
                        try references.append(value.decode(PortholeObjectReference.self))
                    } else { pending.append(contentsOf: fields.values) }
                case let .array(values): pending.append(contentsOf: values)
                case .null, .bool, .integer, .unsignedInteger, .number, .string: break
            }
        }
        guard references.allSatisfy({ $0.scope == invocation.scope })
        else { throw PortholeError.staleScope }
        return references
    }
}
