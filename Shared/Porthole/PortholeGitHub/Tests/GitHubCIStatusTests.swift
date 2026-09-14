import Foundation
import PortholeGitHub
import Testing

struct GitHubCIStatusTests {
    @Test func skippedChecksDoNotClaimAnExecutedBuild() throws {
        let result = try GitHubCIStatus(commit: GitHubTestFixtures.commit, checks: [
            GitHubCICheck(name: "Build", state: .skipped, detailsURL: nil),
        ])
        #expect(result.state == .skipped)
    }

    @Test func noChecksDoesNotClaimSuccess() throws {
        #expect(try GitHubCIStatus(commit: GitHubTestFixtures.commit, checks: []).state == .pending)
    }

    @Test func joinsNativeChecksAndExternalProviderStatuses() async throws {
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"check_runs":[{"name":"Build","status":"completed","conclusion":"success","html_url":"https://github.com/sample-user/Example/actions/runs/1"}]}"#,
            ),
            .response(
                200,
                #"{"statuses":[{"context":"CircleCI","state":"pending","target_url":"https://circleci.com/gh/sample-user/Example/1"}]}"#,
            ),
        ])
        let client = try await GitHubRepositoryClient(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore.authenticated(),
            now: { GitHubTestFixtures.now },
        )
        let result = try await client.ciStatus(
            repository: GitHubTestFixtures.repository,
            commit: GitHubTestFixtures.publishedCommit,
        )
        #expect(result.checks.count == 2)
        #expect(result.state == .pending)
        let requests = await transport.requests
        #expect(requests
            .allSatisfy { $0.url?.path.contains("cccccccccccccccccccccccccccccccccccccccc") == true
            })
    }

    @Test func unfamiliarConclusionRemainsUnknown() async throws {
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"check_runs":[{"name":"Build","status":"completed","conclusion":"new_conclusion","html_url":null}]}"#,
            ),
            .response(200, #"{"statuses":[]}"#),
        ])
        let client = try await GitHubRepositoryClient(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore.authenticated(),
            now: { GitHubTestFixtures.now },
        )
        let result = try await client.ciStatus(
            repository: GitHubTestFixtures.repository,
            commit: GitHubTestFixtures.publishedCommit,
        )
        #expect(result.state == .unknown("new_conclusion"))
    }
}
