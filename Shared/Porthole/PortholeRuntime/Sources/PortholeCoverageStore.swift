import Foundation
import PortholeCore

/// Scope-owned source coverage stays separate from executable registrations.
struct PortholeCoverageStore {
    struct Registration {
        let capability: PortholeCapability
        let hasHandler: Bool
    }

    private struct Declaration {
        let module: PortholeModuleID
        let value: PortholeDeclarationCoverage
    }

    private struct Scope {
        var modules: [PortholeModuleID: PortholeModuleCoverage] = [:]
        var declarations: [PortholeSymbolID: Declaration] = [:]
        var encodedBytes = 0
    }

    private let maximumModules: Int
    private let maximumDeclarations: Int
    private let maximumBytes: Int
    private var scopes: [PortholeScopeToken: Scope] = [:]
    private var moduleCount = 0
    private var declarationCount = 0
    private var encodedBytes = 0

    init(maximumModules: Int, maximumDeclarations: Int, maximumBytes: Int) {
        precondition(maximumModules > 0 && maximumDeclarations > 0 && maximumBytes > 0)
        self.maximumModules = maximumModules
        self.maximumDeclarations = maximumDeclarations
        self.maximumBytes = maximumBytes
    }

    mutating func install(
        _ json: String,
        in scope: PortholeScopeToken,
        sources: [String: PortholeSourceFile],
        registration: (PortholeSymbolID) -> Registration?,
    ) throws {
        try Task.checkCancellation()
        guard json.utf8.count <= maximumBytes else {
            throw invalid("The coverage document exceeds its byte limit.")
        }
        let document = try JSONDecoder().decode(
            PortholeCoverageDocument.self,
            from: Data(json.utf8),
        )
        guard document.version == 1 else {
            throw invalid("Unsupported coverage version: \(document.version).")
        }
        guard document.modules.count <= maximumModules else {
            throw invalid("The coverage document exceeds its module limit.")
        }
        var next = scopes[scope] ?? Scope()
        var documentModules: Set<PortholeModuleID> = []
        var addedModules = 0
        var addedDeclarations = 0
        var addedBytes = 0
        for module in document.modules {
            guard !module.module.rawValue.isEmpty,
                  documentModules.insert(module.module).inserted
            else {
                throw invalid("Duplicate or empty coverage module: \(module.module.rawValue).")
            }
            guard module.declarations.count <= maximumDeclarations else {
                throw invalid("The coverage document exceeds its declaration limit.")
            }
            try Task.checkCancellation()
            try validate(module, sources: sources, registration: registration)
            if let previous = next.modules[module.module] {
                guard previous == module else {
                    throw invalid("Conflicting coverage module: \(module.module.rawValue).")
                }
                continue
            }
            guard addedModules < maximumModules - moduleCount,
                  module.declarations
                  .count <= maximumDeclarations - declarationCount - addedDeclarations
            else {
                throw invalid("The coverage module or declaration limit was reached.")
            }
            let bytes = try JSONEncoder().encode(module).count
            guard bytes <= maximumBytes - encodedBytes - addedBytes else {
                throw invalid("The installed coverage byte limit was reached.")
            }
            for declaration in module.declarations {
                guard next.declarations[declaration.id] == nil else {
                    throw invalid("Duplicate coverage declaration: \(declaration.id.rawValue).")
                }
                next.declarations[declaration.id] = Declaration(
                    module: module.module,
                    value: declaration,
                )
            }
            next.modules[module.module] = module
            addedModules += 1
            addedDeclarations += module.declarations.count
            addedBytes += bytes
        }
        next.encodedBytes += addedBytes
        scopes[scope] = next
        moduleCount += addedModules
        declarationCount += addedDeclarations
        encodedBytes += addedBytes
    }

    func validate(
        _ capability: PortholeCapability,
        hasHandler: Bool,
        in scope: PortholeScopeToken,
    ) throws {
        guard let declaration = scopes[scope]?.declarations[capability.id] else { return }
        try validate(
            Registration(capability: capability, hasHandler: hasHandler),
            against: declaration.value,
            module: declaration.module,
        )
    }

    mutating func invalidate(_ scope: PortholeScopeToken) {
        guard let removed = scopes.removeValue(forKey: scope) else { return }
        moduleCount -= removed.modules.count
        declarationCount -= removed.declarations.count
        encodedBytes -= removed.encodedBytes
    }

    func modules(
        in scope: PortholeScopeToken,
        offset: Int,
        limit: Int,
        registration: (PortholeSymbolID) -> Registration?,
    ) throws -> PortholeCoverageModulePage {
        try Task.checkCancellation()
        try bounds(offset: offset, limit: limit)
        let modules = try installedModules(in: scope)
            .sorted { $0.module.rawValue < $1.module.rawValue }
        let items = try modules.dropFirst(offset).prefix(limit).map { module in
            var counts: [PortholeCoverageStatusFilter: Int] = [:]
            for declaration in module.declarations {
                try Task.checkCancellation()
                let entry = entry(
                    declaration,
                    module: module.module,
                    registration: registration(declaration.id),
                )
                counts[status(entry.state), default: 0] += 1
            }
            return PortholeCoverageModuleSummary(
                module: module.module,
                build: module.build,
                sourceFileCount: module.files.count,
                counts: .init(
                    total: module.declarations.count,
                    callable: counts[.callable, default: 0],
                    inspectableSource: counts[.inspectableSource, default: 0],
                    unsupported: counts[.unsupported, default: 0],
                    inactive: counts[.inactive, default: 0],
                    sourceOnly: counts[.sourceOnly, default: 0],
                    excluded: counts[.excluded, default: 0],
                ),
            )
        }
        return .init(scope: scope, total: modules.count, items: Array(items))
    }

    func declarations(
        in scope: PortholeScopeToken,
        query: PortholeCoverageQuery,
        registration: (PortholeSymbolID) -> Registration?,
    ) throws -> PortholeCoveragePage {
        try Task.checkCancellation()
        try bounds(offset: query.offset, limit: query.limit)
        guard query.search.utf8.count <= 4096 else {
            throw invalid("Coverage search must contain at most 4096 UTF-8 bytes.")
        }
        let modules = try installedModules(in: scope)
            .filter { query.module == nil || $0.module == query.module }
            .sorted { $0.module.rawValue < $1.module.rawValue }
        var total = 0
        var items: [PortholeCoverageEntry] = []
        for module in modules {
            for declaration in module.declarations.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
                try Task.checkCancellation()
                let entry = entry(
                    declaration,
                    module: module.module,
                    registration: registration(declaration.id),
                )
                guard query.status == .all || query.status == status(entry.state),
                      matches(entry, search: query.search) else { continue }
                if total >= query.offset, items.count < query.limit { items.append(entry) }
                total += 1
            }
        }
        return .init(scope: scope, total: total, items: items)
    }

    private func installedModules(in scope: PortholeScopeToken) throws -> [PortholeModuleCoverage] {
        guard let installed = scopes[scope] else {
            throw PortholeError
                .operationFailed("Source coverage has not been installed in this scope.")
        }
        return Array(installed.modules.values)
    }

    private func validate(
        _ module: PortholeModuleCoverage,
        sources: [String: PortholeSourceFile],
        registration: (PortholeSymbolID) -> Registration?,
    ) throws {
        var files: [String: String] = [:]
        for file in module.files {
            guard !file.path.isEmpty, files[file.path] == nil,
                  sources[file.path]?.sha256 == file.sha256
            else {
                throw invalid("Missing, duplicate, or mismatched coverage source: \(file.path).")
            }
            files[file.path] = file.sha256
        }
        var identities: Set<PortholeSymbolID> = []
        for declaration in module.declarations {
            try Task.checkCancellation()
            guard !declaration.id.rawValue.isEmpty,
                  identities.insert(declaration.id).inserted
            else {
                throw invalid(
                    "Duplicate or empty coverage declaration: \(declaration.id.rawValue).",
                )
            }
            switch declaration.origin {
                case .generated, .sourceOnly:
                    guard declaration.kind != .excludedFile,
                          let source = declaration.source, source.line > 0,
                          let hash = declaration.sourceSHA256,
                          files[source.path] == hash
                    else {
                        throw invalid(
                            "Coverage source does not match its module: \(declaration.id.rawValue).",
                        )
                    }
                case .excludedFile:
                    guard declaration.kind == .excludedFile,
                          declaration.source == nil, declaration.sourceSHA256 == nil
                    else {
                        throw invalid(
                            "Excluded coverage must not expose source: \(declaration.id.rawValue).",
                        )
                    }
            }
            if declaration.origin != .generated {
                guard case let .unsupported(reason) = declaration.plannedAvailability,
                      !reason.isEmpty
                else {
                    throw invalid(
                        "Source-only and excluded coverage require an unsupported reason.",
                    )
                }
            }
            if let installed = registration(declaration.id) {
                try validate(installed, against: declaration, module: module.module)
            }
        }
    }

    private func validate(
        _ registration: Registration,
        against declaration: PortholeDeclarationCoverage,
        module: PortholeModuleID,
    ) throws {
        let capability = registration.capability
        guard capability.module == module, capability.name == declaration.name,
              capability.source == declaration.source,
              !registration.hasHandler || declaration.origin == .generated
        else {
            throw invalid("Registration conflicts with coverage: \(declaration.id.rawValue).")
        }
    }

    private func entry(
        _ declaration: PortholeDeclarationCoverage,
        module: PortholeModuleID,
        registration: Registration?,
    ) -> PortholeCoverageEntry {
        let state: PortholeCoverageState = switch declaration.origin {
            case .sourceOnly:
                .sourceOnly(reason(declaration.plannedAvailability))
            case .excludedFile:
                .excluded(reason(declaration.plannedAvailability))
            case .generated:
                if let registration {
                    switch registration.capability.availability {
                        case .callable:
                            registration.hasHandler ? .callable : .inspectableSource
                        case .inspectable: .inspectableSource
                        case let .unsupported(reason): .unsupported(reason)
                    }
                } else { .inactive }
        }
        return .init(
            module: module,
            declaration: declaration,
            state: state,
            installedCapabilityID: registration?.capability.id,
        )
    }

    private func matches(_ entry: PortholeCoverageEntry, search: String) -> Bool {
        guard !search.isEmpty else { return true }
        let declaration = entry.declaration
        var fields = [
            entry.module.rawValue,
            declaration.id.rawValue,
            declaration.name,
            declaration.kind.rawValue,
            declaration.signature,
            declaration.source?.path ?? "",
            reason(declaration.plannedAvailability),
            status(entry.state).rawValue,
        ] + declaration.conditions
        switch entry.state {
            case let .unsupported(reason), let .sourceOnly(reason),
                 let .excluded(reason): fields.append(reason)
            case .callable, .inspectableSource, .inactive: break
        }
        return fields.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    private func status(_ state: PortholeCoverageState) -> PortholeCoverageStatusFilter {
        switch state {
            case .callable: .callable
            case .inspectableSource: .inspectableSource
            case .unsupported: .unsupported
            case .inactive: .inactive
            case .sourceOnly: .sourceOnly
            case .excluded: .excluded
        }
    }

    private func reason(_ availability: PortholeAvailability) -> String {
        switch availability {
            case let .unsupported(reason): reason
            case .callable, .inspectable: ""
        }
    }

    private func bounds(offset: Int, limit: Int) throws {
        guard offset >= 0, offset < Int.max, (1 ... 200).contains(limit) else {
            throw invalid("Coverage offset must be 0...\(Int.max - 1); limit must be 1...200.")
        }
    }

    private func invalid(_ message: String) -> PortholeError {
        .invalidArguments(message)
    }
}
