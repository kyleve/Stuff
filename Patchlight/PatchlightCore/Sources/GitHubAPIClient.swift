import Foundation

/// GitHub.com's read client. Every route is assembled below the fixed API
/// origin and every wire identity is validated before becoming a domain value.
public actor GitHubAPIClient: GitHubReading {
    private let credentials: GitHubCredentialManager
    private let transport: any PatchlightHTTPTransport
    private let patchParser: UnifiedPatchParser
    private let fallbackDiff: BoundedMyersDiff
    private var repositoriesByID: [RepositoryID: RepositorySummary] = [:]
    private var conditionalResponses: [ConditionalRequestKey: ConditionalResponse] = [:]

    public init(
        credentials: GitHubCredentialManager,
        transport: any PatchlightHTTPTransport,
    ) {
        self.credentials = credentials
        self.transport = transport
        patchParser = UnifiedPatchParser()
        fallbackDiff = BoundedMyersDiff(limits: .githubFallback, contextLineCount: 3)
    }

    public func viewer() async throws -> GitHubViewer {
        let wire: ViewerWire = try await get(path: ["user"])
        guard !wire.login.isEmpty else { throw GitHubAPIError.invalidResponse }
        return GitHubViewer(
            id: PatchlightAccountID(rawValue: wire.id),
            login: wire.login,
            avatarURL: wire.avatarURL.flatMap(URL.init(string:)),
        )
    }

    public func installations() async throws -> [GitHubInstallationSummary] {
        let installationWires: [InstallationWire] = try await paginated(
            path: ["user", "installations"],
            response: InstallationPageWire.self,
            values: \InstallationPageWire.installations,
        )
        var summaries: [GitHubInstallationSummary] = []
        var index: [RepositoryID: RepositorySummary] = [:]

        for installation in installationWires {
            try Task.checkCancellation()
            guard let accountType = installation.account.accountType else {
                throw GitHubAPIError.invalidResponse
            }
            let installationID = GitHubInstallationID(rawValue: installation.id)
            let repositoryWires: [RepositoryWire] = try await paginated(
                path: ["user", "installations", String(installation.id), "repositories"],
                response: RepositoryPageWire.self,
                values: \RepositoryPageWire.repositories,
            )
            let repositories = try repositoryWires.map {
                try repositorySummary($0, installationID: installationID)
            }.sorted { lhs, rhs in
                lhs.coordinates.displayName.localizedCaseInsensitiveCompare(
                    rhs.coordinates.displayName,
                ) == .orderedAscending
            }
            repositories.forEach { index[$0.id] = $0 }

            let teamDiscovery: TeamDiscoveryAvailability = switch accountType {
                case .user:
                    .notApplicable
                case .organization:
                    installation.permissions["members"] == "read"
                        ? .available
                        : .permissionWithheld
            }
            summaries.append(GitHubInstallationSummary(
                id: installationID,
                accountLogin: installation.account.login,
                accountType: accountType,
                repositories: repositories,
                teamDiscovery: teamDiscovery,
            ))
        }
        repositoriesByID.merge(index) { _, new in new }
        return summaries.sorted {
            $0.accountLogin.localizedCaseInsensitiveCompare($1.accountLogin) == .orderedAscending
        }
    }

    public func repositories() async throws -> [RepositorySummary] {
        let values = try await installations()
        return values.flatMap(\.repositories)
    }

    public func dashboard() async throws -> ReviewDashboard {
        async let viewerValue = viewer()
        async let installationsValue = installations()
        let (viewer, installations) = try await (viewerValue, installationsValue)

        var warnings = installations.compactMap { installation -> GitHubReadWarning? in
            guard installation.teamDiscovery == .permissionWithheld else { return nil }
            return GitHubReadWarning(
                code: .teamDiscoveryUnavailable,
                context: installation.accountLogin,
            )
        }

        async let directResult = searchPullRequests(
            query: "state:open is:pr user-review-requested:@me",
            source: .direct,
        )
        async let ownResult = ownPullRequestPages()

        let accessibleOrganizationLogins = Set(installations.compactMap { installation in
            installation.teamDiscovery == .available ? installation.accountLogin : nil
        })
        let teams: [TeamWire]
        if accessibleOrganizationLogins.isEmpty {
            teams = []
        } else {
            do {
                teams = try await accessibleTeams().filter {
                    accessibleOrganizationLogins.contains($0.organization.login)
                }
            } catch GitHubAPIError.permissionDenied {
                warnings.append(GitHubReadWarning(code: .teamDiscoveryUnavailable, context: nil))
                teams = []
            }
        }

        let direct = try await directResult
        let own = try await ownResult
        warnings.append(contentsOf: direct.warnings)
        warnings.append(contentsOf: own.warnings)

        var requestedByID = Dictionary(uniqueKeysWithValues: direct.values.map { ($0.id, $0) })
        for team in teams {
            try Task.checkCancellation()
            let result = try await searchPullRequests(
                query: "state:open is:pr team-review-requested:\(team.organization.login)/\(team.slug)",
                source: .team(organization: team.organization.login, slug: team.slug),
            )
            warnings.append(contentsOf: result.warnings)
            for pullRequest in result.values where requestedByID[pullRequest.id] == nil {
                requestedByID[pullRequest.id] = pullRequest
            }
        }

        let requests = requestedByID.values.sorted(by: Self.reviewRequestOrdering)
        return ReviewDashboard(
            viewer: viewer,
            reviewRequests: requests,
            ownPullRequests: own.values.sorted { $0.updatedAt > $1.updatedAt },
            installations: installations,
            warnings: Array(Set(warnings)),
        )
    }

    public func reviewRequests() async throws -> [PullRequestSummary] {
        try await dashboard().reviewRequests
    }

    public func ownPullRequests() async throws -> [PullRequestSummary] {
        try await dashboard().ownPullRequests
    }

    public func pullRequests(in repository: RepositoryID) async throws -> [PullRequestSummary] {
        let summary = try await resolveRepository(repository)
        let wires: [PullRequestRESTWire] = try await paginatedArray(
            path: repositoryPath(summary) + ["pulls"],
            query: [URLQueryItem(name: "state", value: "open")],
        )
        return try wires.map {
            try pullRequestSummary($0, repository: summary.coordinates, source: nil)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func workspace(for id: PullRequestID) async throws -> PullRequestWorkspace {
        let repository = try await resolveRepository(id.repository)
        let pullPath = repositoryPath(repository) + ["pulls", String(id.number)]
        let pull: PullRequestRESTWire = try await get(path: pullPath)
        let summary = try pullRequestSummary(pull, repository: repository.coordinates, source: nil)
        let baseOID = try GitObjectID(validating: pull.base.sha)
        let headOID = try GitObjectID(validating: pull.head.sha)

        let requestedCount = min(pull.changedFiles, 3000)
        var fileWires: [PullRequestFileWire] = []
        var page = 1
        while fileWires.count < requestedCount {
            try Task.checkCancellation()
            let pageValues: [PullRequestFileWire] = try await get(
                path: pullPath + ["files"],
                query: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ],
            )
            fileWires.append(contentsOf: pageValues)
            if pageValues.count < 100 { break }
            page += 1
            if page > 30 { break }
        }

        var files: [DiffFile] = []
        files.reserveCapacity(fileWires.count)
        for wire in fileWires {
            try Task.checkCancellation()
            try await files.append(diffFile(
                wire,
                repository: repository,
                baseOID: baseOID,
                headOID: headOID,
            ))
        }

        return try await PullRequestWorkspace(
            summary: summary,
            bodyMarkdown: pull.body,
            baseOID: baseOID,
            files: files,
            isFileListComplete: pull.changedFiles <= 3000 && files.count >= pull.changedFiles,
            repositoryConfiguration: repositoryConfiguration(
                repository: repository,
                baseOID: baseOID,
            ),
        )
    }

    public func blob(
        repository: RepositoryID,
        oid: GitObjectID,
        path _: String,
    ) async throws -> Data {
        let summary = try await resolveRepository(repository)
        return try await rawBlob(repository: summary, oid: oid)
    }

    public func tree(repository: RepositoryID, oid: GitObjectID) async throws -> RepositoryTree {
        let summary = try await resolveRepository(repository)
        let wire: GitTreeWire = try await get(
            path: repositoryPath(summary) + ["git", "trees", oid.rawValue],
            query: [URLQueryItem(name: "recursive", value: "1")],
        )
        let entries = try wire.tree.compactMap { entry -> RepositoryTreeEntry? in
            guard !entry.path.isEmpty else { throw GitHubAPIError.invalidResponse }
            let kind: RepositoryTreeEntry.Kind
            switch entry.kind {
                case "blob": kind = .blob
                case "tree": kind = .tree
                case "commit": return nil
                default: throw GitHubAPIError.invalidResponse
            }
            return try RepositoryTreeEntry(
                path: entry.path,
                kind: kind,
                oid: GitObjectID(validating: entry.sha),
                byteCount: entry.size,
            )
        }
        return RepositoryTree(entries: entries, isComplete: !wire.truncated)
    }

    private func diffFile(
        _ wire: PullRequestFileWire,
        repository: RepositorySummary,
        baseOID: GitObjectID,
        headOID: GitObjectID,
    ) async throws -> DiffFile {
        guard !wire.filename.isEmpty else { throw GitHubAPIError.invalidResponse }
        let status = try DiffFileStatus(wireStatus: wire.status)
        let responseOID = try wire.sha.map { try GitObjectID(validating: $0) }
        let initialBaseOID = status == .removed ? responseOID : nil
        let initialHeadOID = status == .removed ? nil : responseOID

        if let patch = wire.patch {
            do {
                return try DiffFile(
                    path: wire.filename,
                    previousPath: wire.previousFilename,
                    status: status,
                    additions: wire.additions,
                    deletions: wire.deletions,
                    baseBlobOID: initialBaseOID,
                    headBlobOID: initialHeadOID,
                    availability: .complete,
                    hunks: patchParser.parse(patch, path: wire.filename),
                )
            } catch {
                return DiffFile(
                    path: wire.filename,
                    previousPath: wire.previousFilename,
                    status: status,
                    additions: wire.additions,
                    deletions: wire.deletions,
                    baseBlobOID: initialBaseOID,
                    headBlobOID: initialHeadOID,
                    availability: .unavailable(reason: error.localizedDescription),
                    hunks: [],
                )
            }
        }

        let baseBlob: ResolvedBlob
        let headBlob: ResolvedBlob
        do {
            baseBlob = try await resolvedBlob(
                repository: repository,
                path: wire.previousFilename ?? wire.filename,
                commitOID: baseOID,
                knownOID: initialBaseOID,
                absent: status == .added,
            )
            headBlob = try await resolvedBlob(
                repository: repository,
                path: wire.filename,
                commitOID: headOID,
                knownOID: initialHeadOID,
                absent: status == .removed,
            )
        } catch {
            return DiffFile(
                path: wire.filename,
                previousPath: wire.previousFilename,
                status: status,
                additions: wire.additions,
                deletions: wire.deletions,
                baseBlobOID: initialBaseOID,
                headBlobOID: initialHeadOID,
                availability: .unavailable(reason: error.localizedDescription),
                hunks: [],
            )
        }

        do {
            let hunks = try fallbackDiff.diff(
                base: baseBlob.data,
                head: headBlob.data,
                path: wire.filename,
            )
            return DiffFile(
                path: wire.filename,
                previousPath: wire.previousFilename,
                status: status,
                additions: wire.additions,
                deletions: wire.deletions,
                baseBlobOID: baseBlob.oid,
                headBlobOID: headBlob.oid,
                availability: .complete,
                hunks: hunks,
            )
        } catch let error as BoundedMyersDiffError {
            let availability: DiffContentAvailability = switch error {
                case let .tooLarge(baseBytes, headBytes):
                    .tooLarge(baseBytes: baseBytes, headBytes: headBytes)
                case .undecodable:
                    .binary
                case .tooManyLines, .workLimitExceeded:
                    .unavailable(reason: error.localizedDescription)
            }
            return DiffFile(
                path: wire.filename,
                previousPath: wire.previousFilename,
                status: status,
                additions: wire.additions,
                deletions: wire.deletions,
                baseBlobOID: baseBlob.oid,
                headBlobOID: headBlob.oid,
                availability: availability,
                hunks: [],
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DiffFile(
                path: wire.filename,
                previousPath: wire.previousFilename,
                status: status,
                additions: wire.additions,
                deletions: wire.deletions,
                baseBlobOID: baseBlob.oid,
                headBlobOID: headBlob.oid,
                availability: .unavailable(reason: error.localizedDescription),
                hunks: [],
            )
        }
    }

    private func resolvedBlob(
        repository: RepositorySummary,
        path: String,
        commitOID: GitObjectID,
        knownOID: GitObjectID?,
        absent: Bool,
    ) async throws -> ResolvedBlob {
        if absent { return ResolvedBlob(oid: nil, data: Data()) }
        let oid: GitObjectID
        if let knownOID {
            oid = knownOID
        } else {
            let metadata: ContentMetadataWire = try await get(
                path: repositoryPath(repository) + ["contents"] + pathComponents(path),
                query: [URLQueryItem(name: "ref", value: commitOID.rawValue)],
            )
            guard metadata.kind == "file" else { throw GitHubAPIError.invalidResponse }
            oid = try GitObjectID(validating: metadata.sha)
        }
        let data = try await rawBlob(repository: repository, oid: oid)
        return ResolvedBlob(oid: oid, data: data)
    }

    private func rawBlob(repository: RepositorySummary, oid: GitObjectID) async throws -> Data {
        let response = try await request(
            method: .get,
            path: repositoryPath(repository) + ["git", "blobs", oid.rawValue],
            accept: "application/vnd.github.raw+json",
        )
        return response.body
    }

    private func repositoryConfiguration(
        repository: RepositorySummary,
        baseOID: GitObjectID,
    ) async throws -> RepositoryConfigurationState {
        do {
            let metadata: ContentMetadataWire = try await get(
                path: repositoryPath(repository) + ["contents", ".patchlight.json"],
                query: [URLQueryItem(name: "ref", value: baseOID.rawValue)],
            )
            guard metadata.kind == "file" else {
                return .invalid(
                    "The base revision's .patchlight.json is not a regular file; Patchlight is using built-in policy.",
                )
            }
            let oid = try GitObjectID(validating: metadata.sha)
            let data = try await rawBlob(repository: repository, oid: oid)
            return try .loaded(PatchlightRepositoryConfigurationV1.decode(data))
        } catch GitHubAPIError.notFound {
            return .absent
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    private func resolveRepository(_ id: RepositoryID) async throws -> RepositorySummary {
        if let existing = repositoriesByID[id] { return existing }
        let wire: RepositoryWire = try await get(path: ["repositories", String(id.rawValue)])
        // A repository loaded by ID can still be associated with its installation
        // after the dashboard refresh; use the owning installation when known.
        let knownInstallation = repositoriesByID.values.first {
            $0.coordinates.owner == wire.owner.login
        }?.installationID
        let installationID = knownInstallation ?? wire.installationID
            .map(GitHubInstallationID.init(rawValue:))
        let summary = try repositorySummary(wire, installationID: installationID)
        repositoriesByID[id] = summary
        return summary
    }

    private func accessibleTeams() async throws -> [TeamWire] {
        try await paginatedArray(path: ["user", "teams"], query: [])
    }

    private func searchPullRequests(
        query: String,
        source: ReviewRequestSource,
    ) async throws -> PageResult<PullRequestSummary> {
        var cursor: String?
        var values: [PullRequestSummary] = []
        var warnings: [GitHubReadWarning] = []
        repeat {
            try Task.checkCancellation()
            let response: GraphQLResponse<SearchDataWire> = try await graphQL(
                query: Self.searchQuery,
                variables: SearchVariables(query: query, cursor: cursor),
            )
            guard let search = response.data?.search else {
                throw GitHubAPIError.graphQL(response.errors?.map(\.message) ?? [])
            }
            if let errors = response.errors, !errors.isEmpty {
                warnings.append(GitHubReadWarning(
                    code: .partialGraphQLResponse,
                    context: errors.map(\.message).joined(separator: " • "),
                ))
            }
            try values.append(contentsOf: search.nodes.map {
                try pullRequestSummary($0, source: source)
            })
            cursor = search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
        } while cursor != nil
        return PageResult(values: values, warnings: warnings)
    }

    private func ownPullRequestPages() async throws -> PageResult<PullRequestSummary> {
        var cursor: String?
        var values: [PullRequestSummary] = []
        var warnings: [GitHubReadWarning] = []
        repeat {
            try Task.checkCancellation()
            let response: GraphQLResponse<OwnPullRequestsDataWire> = try await graphQL(
                query: Self.ownPullRequestsQuery,
                variables: CursorVariables(cursor: cursor),
            )
            guard let connection = response.data?.viewer.pullRequests else {
                throw GitHubAPIError.graphQL(response.errors?.map(\.message) ?? [])
            }
            if let errors = response.errors, !errors.isEmpty {
                warnings.append(GitHubReadWarning(
                    code: .partialGraphQLResponse,
                    context: errors.map(\.message).joined(separator: " • "),
                ))
            }
            try values.append(contentsOf: connection.nodes.map {
                try pullRequestSummary($0, source: nil)
            })
            cursor = connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : nil
        } while cursor != nil
        return PageResult(values: values, warnings: warnings)
    }

    private func pullRequestSummary(
        _ wire: PullRequestNodeWire,
        source: ReviewRequestSource?,
    ) throws -> PullRequestSummary {
        guard !wire.repository.name.isEmpty, !wire.repository.owner.login.isEmpty,
              !wire.repository.owner.login.contains("/"), !wire.repository.name.contains("/")
        else {
            throw GitHubAPIError.invalidResponse
        }
        let repositoryID = RepositoryID(rawValue: wire.repository.databaseID)
        let coordinates = RepositoryCoordinates(
            owner: wire.repository.owner.login,
            name: wire.repository.name,
        )
        return try PullRequestSummary(
            id: PullRequestID(repository: repositoryID, number: wire.number),
            repository: coordinates,
            title: wire.title,
            authorLogin: wire.author?.login ?? "[deleted]",
            isDraft: wire.isDraft,
            headOID: GitObjectID(validating: wire.headRefOID),
            createdAt: wire.createdAt ?? wire.updatedAt,
            updatedAt: wire.updatedAt,
            reviewRequestSource: source,
            actionability: wire.actionability,
        )
    }

    private func pullRequestSummary(
        _ wire: PullRequestRESTWire,
        repository: RepositoryCoordinates,
        source: ReviewRequestSource?,
    ) throws -> PullRequestSummary {
        try PullRequestSummary(
            id: PullRequestID(
                repository: RepositoryID(rawValue: wire.base.repository.id),
                number: wire.number,
            ),
            repository: repository,
            title: wire.title,
            authorLogin: wire.user?.login ?? "[deleted]",
            isDraft: wire.draft,
            headOID: GitObjectID(validating: wire.head.sha),
            createdAt: wire.createdAt ?? wire.updatedAt,
            updatedAt: wire.updatedAt,
            reviewRequestSource: source,
            actionability: wire.draft ? .draft : .waiting,
        )
    }

    private func repositorySummary(
        _ wire: RepositoryWire,
        installationID: GitHubInstallationID?,
    ) throws -> RepositorySummary {
        guard !wire.owner.login.isEmpty, !wire.name.isEmpty,
              !wire.owner.login.contains("/"), !wire.name.contains("/")
        else {
            throw GitHubAPIError.invalidResponse
        }
        return RepositorySummary(
            id: RepositoryID(rawValue: wire.id),
            coordinates: RepositoryCoordinates(owner: wire.owner.login, name: wire.name),
            installationID: installationID,
            isPrivate: wire.isPrivate,
            defaultBranch: wire.defaultBranch,
        )
    }

    private func graphQL<Payload: Decodable>(
        query: String,
        variables: some Encodable & Sendable,
    ) async throws -> GraphQLResponse<Payload> {
        let body = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let response = try await request(
            method: .post,
            path: ["graphql"],
            body: body,
        )
        return try decode(GraphQLResponse<Payload>.self, from: response.body)
    }

    private func paginated<Page: Decodable, Value>(
        path: [String],
        response _: Page.Type,
        values: KeyPath<Page, [Value]>,
    ) async throws -> [Value] {
        var pageNumber = 1
        var result: [Value] = []
        while true {
            try Task.checkCancellation()
            let page: Page = try await get(
                path: path,
                query: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(pageNumber)),
                ],
            )
            let pageValues = page[keyPath: values]
            result.append(contentsOf: pageValues)
            if pageValues.count < 100 { return result }
            pageNumber += 1
        }
    }

    private func paginatedArray<Value: Decodable>(
        path: [String],
        query: [URLQueryItem] = [],
    ) async throws -> [Value] {
        var pageNumber = 1
        var result: [Value] = []
        while true {
            try Task.checkCancellation()
            let pageValues: [Value] = try await get(
                path: path,
                query: query + [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(pageNumber)),
                ],
            )
            result.append(contentsOf: pageValues)
            if pageValues.count < 100 { return result }
            pageNumber += 1
        }
    }

    private func get<Value: Decodable>(
        path: [String],
        query: [URLQueryItem] = [],
    ) async throws -> Value {
        let response = try await request(method: .get, path: path, query: query)
        return try decode(Value.self, from: response.body)
    }

    private func request(
        method: PatchlightHTTPMethod,
        path: [String],
        query: [URLQueryItem] = [],
        body: Data? = nil,
        accept: String = "application/vnd.github+json",
    ) async throws -> PatchlightHTTPResponse {
        let accessToken = try await credentials.accessToken()
        let url = try Self.apiURL(path: path, query: query)
        var headers = [
            "Accept": accept,
            "Authorization": "Bearer \(accessToken.rawValue)",
            "X-GitHub-Api-Version": "2026-03-10",
        ]
        if body != nil { headers["Content-Type"] = "application/json" }
        let conditionalKey = method == .get ? ConditionalRequestKey(url: url, accept: accept) : nil
        if let conditionalKey, let cached = conditionalResponses[conditionalKey] {
            headers["If-None-Match"] = cached.etag
        }
        let response = try await transport.send(PatchlightHTTPRequest(
            method: method,
            url: url,
            headers: headers,
            body: body,
        ))
        if response.statusCode == 304, let conditionalKey,
           let cached = conditionalResponses[conditionalKey]
        {
            return PatchlightHTTPResponse(
                statusCode: 200,
                headers: cached.headers,
                body: cached.body,
            )
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw Self.apiError(response)
        }
        if let conditionalKey, response.body.count <= 2 * 1024 * 1024,
           let etag = response.header("etag")
        {
            conditionalResponses[conditionalKey] = ConditionalResponse(
                etag: etag,
                headers: response.headers,
                body: response.body,
            )
        }
        return response
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = fractional.date(from: value) { return date }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                guard let date = plain.date(from: value) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid ISO-8601 date",
                    )
                }
                return date
            }
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubAPIError.invalidResponse
        }
    }

    private func repositoryPath(_ repository: RepositorySummary) -> [String] {
        ["repos", repository.coordinates.owner, repository.coordinates.name]
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func reviewRequestOrdering(
        _ lhs: PullRequestSummary,
        _ rhs: PullRequestSummary,
    ) -> Bool {
        let leftPriority = lhs.reviewRequestSource == .direct ? 0 : 1
        let rightPriority = rhs.reviewRequestSource == .direct ? 0 : 1
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func apiURL(path: [String], query: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedPath = "/" + path.map { component in
            component.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }.joined(separator: "/")
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GitHubAPIError.invalidRoute }
        return url
    }

    private static func apiError(_ response: PatchlightHTTPResponse) -> GitHubAPIError {
        let message: String?
        do {
            message = try JSONDecoder().decode(APIMessageWire.self, from: response.body).message
        } catch {
            // HTTP status remains the authoritative failure when GitHub omits
            // its optional human-readable error envelope.
            message = nil
        }
        switch response.statusCode {
            case 401:
                return .authenticationExpired
            case 403 where response.header("x-ratelimit-remaining") == "0":
                let reset = response.header("x-ratelimit-reset")
                    .flatMap(TimeInterval.init)
                    .map { Date(timeIntervalSince1970: $0) }
                return .rateLimited(resetAt: reset)
            case 403:
                return .permissionDenied(message)
            case 404:
                return .notFound
            default:
                return .httpStatus(response.statusCode, message)
        }
    }

    private static let searchQuery = """
    query PatchlightRequestedReviews($query: String!, $cursor: String) {
      search(query: $query, type: ISSUE, first: 100, after: $cursor) {
        nodes {
          ... on PullRequest {
            number title isDraft headRefOid createdAt updatedAt reviewDecision
            author { login }
            repository { databaseId name owner { login } }
            reviewThreads(first: 100) {
              nodes { isResolved }
              pageInfo { hasNextPage }
            }
            commits(last: 1) {
              nodes { commit { statusCheckRollup { state } } }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    private static let ownPullRequestsQuery = """
    query PatchlightOwnPullRequests($cursor: String) {
      viewer {
        pullRequests(first: 100, after: $cursor, states: OPEN,
          orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            number title isDraft headRefOid createdAt updatedAt reviewDecision
            author { login }
            repository { databaseId name owner { login } }
            reviewThreads(first: 100) {
              nodes { isResolved }
              pageInfo { hasNextPage }
            }
            commits(last: 1) {
              nodes { commit { statusCheckRollup { state } } }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """
}

public enum GitHubAPIError: LocalizedError, Equatable, Sendable {
    case invalidRoute
    case invalidResponse
    case authenticationExpired
    case permissionDenied(String?)
    case rateLimited(resetAt: Date?)
    case notFound
    case graphQL([String])
    case httpStatus(Int, String?)

    public var errorDescription: String? {
        switch self {
            case .invalidRoute:
                "Patchlight could not construct a safe GitHub route."
            case .invalidResponse:
                "GitHub returned data Patchlight could not validate."
            case .authenticationExpired:
                "GitHub authorization expired. Reconnect to keep local drafts."
            case let .permissionDenied(message):
                message ?? "The Patchlight GitHub App does not have permission for this operation."
            case let .rateLimited(resetAt):
                resetAt.map { "GitHub's API limit resets at \($0.formatted())." }
                    ?? "GitHub's API rate limit has been reached."
            case .notFound:
                "GitHub could not find this resource, or the installation cannot access it."
            case let .graphQL(messages):
                messages.isEmpty
                    ? "GitHub returned an incomplete GraphQL response."
                    : messages.joined(separator: " • ")
            case let .httpStatus(status, message):
                message ?? "GitHub returned HTTP \(status)."
        }
    }
}

extension DiffFileStatus {
    fileprivate init(wireStatus: String) throws {
        self = switch wireStatus {
            case "added": .added
            case "modified": .modified
            case "removed": .removed
            case "renamed": .renamed
            case "copied": .copied
            case "changed": .changed
            default: throw GitHubAPIError.invalidResponse
        }
    }
}

private struct ResolvedBlob {
    let oid: GitObjectID?
    let data: Data
}

private struct ConditionalRequestKey: Hashable {
    let url: URL
    let accept: String
}

private struct ConditionalResponse {
    let etag: String
    let headers: [String: String]
    let body: Data
}

private struct PageResult<Value: Sendable> {
    let values: [Value]
    let warnings: [GitHubReadWarning]
}

private struct ViewerWire: Decodable {
    let id: Int64
    let login: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case avatarURL = "avatar_url"
    }
}

private struct InstallationPageWire: Decodable {
    let installations: [InstallationWire]
}

private struct InstallationWire: Decodable {
    let id: Int64
    let account: AccountWire
    let permissions: [String: String]
}

private struct AccountWire: Decodable {
    let login: String
    let type: String

    var accountType: GitHubInstallationSummary.AccountType? {
        switch type {
            case "User": .user
            case "Organization": .organization
            default: nil
        }
    }
}

private struct RepositoryPageWire: Decodable {
    let repositories: [RepositoryWire]
}

private struct RepositoryWire: Decodable {
    let id: Int64
    let name: String
    let owner: LoginWire
    let isPrivate: Bool
    let defaultBranch: String
    let installationID: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case owner
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case installationID = "installation_id"
    }
}

private struct TeamWire: Decodable {
    let slug: String
    let organization: LoginWire
}

private struct LoginWire: Decodable {
    let login: String
}

private struct PullRequestRESTWire: Decodable {
    let number: Int
    let title: String
    let body: String?
    let user: LoginWire?
    let draft: Bool
    let createdAt: Date?
    let updatedAt: Date
    let head: PullRefWire
    let base: PullRefWire
    let changedFiles: Int

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case user
        case draft
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case head
        case base
        case changedFiles = "changed_files"
    }
}

private struct PullRefWire: Decodable {
    let sha: String
    let repository: PullRepositoryWire

    enum CodingKeys: String, CodingKey {
        case sha
        case repository = "repo"
    }
}

private struct PullRepositoryWire: Decodable {
    let id: Int64
}

private struct PullRequestFileWire: Decodable {
    let sha: String?
    let filename: String
    let status: String
    let additions: Int
    let deletions: Int
    let patch: String?
    let previousFilename: String?

    enum CodingKeys: String, CodingKey {
        case sha
        case filename
        case status
        case additions
        case deletions
        case patch
        case previousFilename = "previous_filename"
    }
}

private struct ContentMetadataWire: Decodable {
    let kind: String
    let sha: String

    enum CodingKeys: String, CodingKey {
        case kind = "type"
        case sha
    }
}

private struct GitTreeWire: Decodable {
    let tree: [GitTreeEntryWire]
    let truncated: Bool
}

private struct GitTreeEntryWire: Decodable {
    let path: String
    let kind: String
    let sha: String
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case kind = "type"
        case sha
        case size
    }
}

private struct APIMessageWire: Decodable {
    let message: String
}

private struct GraphQLRequest<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLErrorWire]?
}

private struct GraphQLErrorWire: Decodable {
    let message: String
}

private struct SearchVariables: Encodable {
    let query: String
    let cursor: String?
}

private struct CursorVariables: Encodable {
    let cursor: String?
}

private struct SearchDataWire: Decodable {
    let search: PullRequestConnectionWire
}

private struct OwnPullRequestsDataWire: Decodable {
    let viewer: OwnViewerWire
}

private struct OwnViewerWire: Decodable {
    let pullRequests: PullRequestConnectionWire
}

private struct PullRequestConnectionWire: Decodable {
    let nodes: [PullRequestNodeWire]
    let pageInfo: PageInfoWire
}

private struct PageInfoWire: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct PullRequestNodeWire: Decodable {
    let number: Int
    let title: String
    let isDraft: Bool
    let headRefOID: String
    let createdAt: Date?
    let updatedAt: Date
    let reviewDecision: String?
    let author: LoginWire?
    let repository: GraphQLRepositoryWire
    let reviewThreads: ReviewThreadSummaryConnectionWire?
    let commits: CommitSummaryConnectionWire?

    var actionability: ReviewActionability {
        if isDraft { return .draft }
        if reviewThreads?.nodes.contains(where: { !$0.isResolved }) == true ||
            reviewThreads?.pageInfo.hasNextPage == true
        {
            return .unresolvedThreads
        }
        switch commits?.nodes.last?.commit.statusCheckRollup?.state {
            case "PENDING", "EXPECTED": return .pendingChecks
            case "FAILURE", "ERROR": return .failedChecks
            case "SUCCESS", nil: break
            default: break
        }
        if reviewDecision == "CHANGES_REQUESTED" { return .changesRequested }
        return .waiting
    }

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case isDraft
        case headRefOID = "headRefOid"
        case createdAt
        case updatedAt
        case reviewDecision
        case author
        case repository
        case reviewThreads
        case commits
    }
}

private struct ReviewThreadSummaryConnectionWire: Decodable {
    let nodes: [ReviewThreadSummaryWire]
    let pageInfo: PageInfoWire
}

private struct ReviewThreadSummaryWire: Decodable {
    let isResolved: Bool
}

private struct CommitSummaryConnectionWire: Decodable {
    let nodes: [CommitSummaryNodeWire]
}

private struct CommitSummaryNodeWire: Decodable {
    let commit: CommitSummaryWire
}

private struct CommitSummaryWire: Decodable {
    let statusCheckRollup: CheckRollupSummaryWire?
}

private struct CheckRollupSummaryWire: Decodable {
    let state: String
}

private struct GraphQLRepositoryWire: Decodable {
    let databaseID: Int64
    let name: String
    let owner: LoginWire

    enum CodingKeys: String, CodingKey {
        case databaseID = "databaseId"
        case name
        case owner
    }
}
