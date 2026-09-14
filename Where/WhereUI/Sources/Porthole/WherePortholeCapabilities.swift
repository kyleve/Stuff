import Foundation
import PortholeRuntime
import RegionKit
import WhereCore

/// Focused adapters use the injected services' ordinary reads and explicitly copied replay values.
enum WherePortholeCapabilities {
    @MainActor
    static func install(
        scope: WhereScope,
        registry: PortholeRegistry,
        token: PortholeScopeToken,
    ) async throws {
        let services = scope.services
        let roots: [PortholeObjectReference] = try await [
            registry.retain(services, in: token),
            registry.retain(services.reports, in: token),
            registry.retain(services.resolution, in: token),
            registry.retain(services.journal, in: token),
            registry.retain(services.recording, in: token),
            registry.retain(services.ingestor, in: token),
        ]
        try await registry.capture(PortholeContext(
            id: .init(rawValue: "where.services"),
            title: "Where services",
            scope: token,
            capturedAt: Date(),
            values: .object(["driftThresholdMeters": .integer(Int64(scope.preferences
                    .driftThresholdMeters))]),
            objects: roots,
            links: [],
            source: .init(path: "Where/WhereCore/Sources/WhereServices.swift", line: 36),
        ))
        try await register(
            "where.investigation.capture",
            summary: "Capture current detector inputs under one persistence snapshot. This is current evidence, not a recording of a past scan.",
            parameters: [
                parameter("year", .integer),
                parameter("primaryRegions", .array(.string)),
                parameter("driftThresholdMeters", .number),
            ],
            effect: .read,
            registry: registry,
            scope: token,
        ) { invocation, registry in
            let year = try required("year", invocation).decode(Int.self)
            guard (1 ... 9999).contains(year)
            else { throw PortholeError.invalidArguments("year must be 1...9999") }
            let regions = try required("primaryRegions", invocation).decode([Region].self)
            let threshold = try required("driftThresholdMeters", invocation).decode(Double.self)
            guard threshold.isFinite,
                  threshold >= 0
            else {
                throw PortholeError.invalidArguments("threshold must be finite and nonnegative")
            }
            let snapshot = try await services.reports.investigation(
                year: year,
                primaryRegions: regions,
                driftThresholdMeters: threshold,
                now: Date(),
            )
            return try await registry.encode(snapshot, in: invocation.scope, retention: .bounded(
                pool: .init(rawValue: "where.investigations"),
                maximumCount: 4,
            ))
        }
        try await register(
            "where.investigation.day",
            summary: "Inspect captured GPS inputs, attribution, dismissal state and configuration for a logical day.",
            parameters: [parameter("investigation", .any), parameter("day", .string)],
            effect: .read,
            registry: registry,
            scope: token,
        ) { invocation, registry in
            let snapshot = try await registry.decode(
                required("investigation", invocation),
                as: DataIssueInvestigation.self,
                in: invocation.scope,
            )
            guard let parent = try required("investigation", invocation)["$reference"] else {
                throw PortholeError
                    .invalidArguments("investigation must be a captured object reference")
            }
            let parentReference = try parent.decode(PortholeObjectReference.self)
            guard let day = try CalendarDay(iso: required("day", invocation).decode(String.self))
            else {
                throw PortholeError.invalidArguments("day must be YYYY-MM-DD")
            }
            let input = snapshot.input
            let samples = input.daySamples.samples(on: day)
            return try await .object([
                "capturedAt": .encoding(snapshot.capturedAt),
                "evidenceKind": .string("observed current snapshot"),
                "day": .string(day.description),
                "samples": .encoding(samples),
                "presence": .encoding(input.report.days.first { $0.day == day }),
                "otherCoordinates": .encoding(input.otherDayCoordinates[day] ?? []),
                "attribution": .array(samples
                    .map { .string(input.attributor.region(at: $0.coordinate).rawValue) }),
                "primaryRegions": .encoding(input.primaryRegions),
                "loadedRegions": .encoding(input.attributor.loadedRegions),
                "driftThresholdMeters": .number(input.driftThresholdMeters),
                "timeZone": .string(input.calendar.timeZone.identifier),
                "dismissedIssueIDs": .encoding(snapshot.dismissedIssueIDs),
                "input": registry.encodeChild(
                    input,
                    key: .init(rawValue: "input"),
                    of: parentReference,
                    in: invocation.scope,
                ),
                "attributor": registry.encodeChild(
                    input.attributor,
                    key: .init(rawValue: "attributor"),
                    of: parentReference,
                    in: invocation.scope,
                ),
            ])
        }
        try await register(
            "where.scanner.state",
            summary: "Inspect the live scanner cache without starting a scan. Historical detector inputs are not retained.",
            parameters: [],
            effect: .read,
            registry: registry,
            scope: token,
        ) { _, _ in
            try await .encoding(services.resolution.diagnosticState)
        }
        try await register(
            "where.investigation.replay",
            summary: "Run a selected production detector on copied inputs. Returns reproduced results, without changing the live scanner or data.",
            parameters: [parameter("investigation", .any), parameter("category", .string)],
            effect: .isolated,
            registry: registry,
            scope: token,
        ) { invocation, registry in
            let snapshot = try await registry.decode(
                required("investigation", invocation),
                as: DataIssueInvestigation.self,
                in: invocation.scope,
            )
            let category = try required("category", invocation).decode(DataIssueCategory.self)
            guard let parent = try required("investigation", invocation)["$reference"] else {
                throw PortholeError
                    .invalidArguments("investigation must be a captured object reference")
            }
            let parentReference = try parent.decode(PortholeObjectReference.self)
            var issues: [PortholeValue] = []
            for issue in snapshot.replay(category: category) {
                try await issues.append(.object([
                    "id": .encoding(issue.id),
                    "category": .encoding(issue.category),
                    "day": .string(issue.sortKey.description),
                    "dismissed": .bool(snapshot.dismissedIssueIDs.contains(issue.id)),
                    "value": registry.encodeChild(
                        issue,
                        key: .init(rawValue: PortholeValue.encoding(issue.id).json()),
                        of: parentReference,
                        in: invocation.scope,
                    ),
                ]))
            }
            return .object(["evidenceKind": .string("reproduced"), "issues": .array(issues)])
        }
    }

    private static func required(
        _ key: String,
        _ invocation: PortholeInvocation,
    ) throws -> PortholeValue {
        guard let value = invocation.arguments[key]
        else { throw PortholeError.invalidArguments("Missing \(key)") }
        return value
    }

    private static func parameter(_ name: String, _ schema: PortholeSchema) -> PortholeParameter {
        .init(name: name, summary: name, schema: schema, required: true)
    }

    private static func register(
        _ name: String,
        summary: String,
        parameters: [PortholeParameter],
        effect: PortholeEffect,
        registry: PortholeRegistry,
        scope: PortholeScopeToken,
        handler: @escaping PortholeRegistry.Handler,
    ) async throws {
        try await registry.register(
            PortholeCapability(
                id: .init(rawValue: name),
                module: .init(rawValue: "WhereCore"),
                name: name,
                summary: summary,
                parameters: parameters,
                result: .any,
                effect: effect,
                source: .init(
                    path: "Where/WhereCore/Sources/Diagnostics/DataIssueInvestigation.swift",
                    line: 1,
                ),
                ownership: .adapter,
                availability: .callable,
            ),
            in: scope,
            handler: handler,
        )
    }
}
