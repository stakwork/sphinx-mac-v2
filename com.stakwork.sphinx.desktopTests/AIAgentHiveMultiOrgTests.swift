//
//  AIAgentHiveMultiOrgTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Covers multi-org Hive support: resolveOrg, org list caching/pruning,
//  per-org canvas-history isolation, resolveProposalOrg, and prompt
//  sanitization for the query_hive_graph org list.
//
//  Uses a dedicated UserDefaults(suiteName:) swapped in for UserDefaults.standard
//  via KVO-free direct key writes is not possible since DefaultKey always reads
//  UserDefaults.standard — so these tests write/read the same standard-domain
//  keys the app uses, but clear them completely in setUp/tearDown so no state
//  leaks between tests or into other test files.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class AIAgentHiveMultiOrgTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        clearAllHiveKeys()
    }

    override func tearDown() {
        clearAllHiveKeys()
        super.tearDown()
    }

    private func clearAllHiveKeys() {
        UserDefaults.Keys.hiveOrgs.removeValue()
        UserDefaults.Keys.hiveOrgSlugsByOrg.removeValue()
        UserDefaults.Keys.hiveConversationIdByOrg.removeValue()
        UserDefaults.Keys.hiveCanvasChatHistoryByOrg.removeValue()
        UserDefaults.Keys.hivePendingProposal.removeValue()
        UserDefaults.Keys.hiveOrgId.removeValue()
        UserDefaults.Keys.hiveGithubLogin.removeValue()
        UserDefaults.Keys.hiveOrgSlugs.removeValue()
        UserDefaults.Keys.hiveOrgSlugsCacheDate.removeValue()
        AIAgentManager.sharedInstance.pendingProposal = nil
        AIAgentManager.sharedInstance.canvasChatHistory = []
    }

    // MARK: - Fixtures

    private func org(_ id: String, login: String, name: String) -> HiveOrg {
        HiveOrg(id: id, githubLogin: login, name: name)
    }

    private func proposalToolCall(proposalId: String) -> AIAgentManager.ToolCall {
        AIAgentManager.ToolCall(
            id: "tc-\(proposalId)",
            toolName: "propose_feature",
            status: "output-available",
            input: ["proposalId": proposalId],
            output: nil
        )
    }

    private func historyWithProposal(_ proposalId: String) -> [AIAgentManager.CanvasChatMessage] {
        [
            AIAgentManager.CanvasChatMessage(role: "user", content: "hello"),
            AIAgentManager.CanvasChatMessage(
                role: "assistant",
                content: "proposed",
                toolCalls: [proposalToolCall(proposalId: proposalId)]
            )
        ]
    }

    // MARK: - resolveOrg

    func testResolveOrg_singleOrgNoRef() {
        let orgs = [org("1", login: "acme", name: "Acme")]
        let result = AIAgentManager.resolveOrg(nil, in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "1")
        default: XCTFail("expected success")
        }
    }

    func testResolveOrg_singleOrgWithRef() {
        let orgs = [org("1", login: "acme", name: "Acme")]
        let result = AIAgentManager.resolveOrg("acme", in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "1")
        default: XCTFail("expected success")
        }
    }

    func testResolveOrg_multiOrgNoRef_isAmbiguous() {
        let orgs = [org("1", login: "acme", name: "Acme"), org("2", login: "beta", name: "Beta")]
        let result = AIAgentManager.resolveOrg(nil, in: orgs)
        switch result {
        case .failure(.ambiguous(let candidates)): XCTAssertEqual(candidates.count, 2)
        default: XCTFail("expected ambiguous")
        }
    }

    func testResolveOrg_matchesByLoginCaseInsensitiveWithWhitespace() {
        let orgs = [org("1", login: "Acme-Org", name: "Acme")]
        let result = AIAgentManager.resolveOrg("  acme-org  ", in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "1")
        default: XCTFail("expected success")
        }
    }

    func testResolveOrg_matchesById() {
        let orgs = [org("org-123", login: "acme", name: "Acme"), org("org-456", login: "beta", name: "Beta")]
        let result = AIAgentManager.resolveOrg("ORG-456", in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.githubLogin, "beta")
        default: XCTFail("expected success")
        }
    }

    func testResolveOrg_matchesByName() {
        let orgs = [org("1", login: "acme", name: "Acme Corp"), org("2", login: "beta", name: "Beta Inc")]
        let result = AIAgentManager.resolveOrg("beta inc", in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "2")
        default: XCTFail("expected success")
        }
    }

    func testResolveOrg_duplicateNamesAreAmbiguous() {
        let orgs = [org("1", login: "acme1", name: "Acme"), org("2", login: "acme2", name: "Acme")]
        let result = AIAgentManager.resolveOrg("acme", in: orgs)
        switch result {
        case .failure(.ambiguous(let candidates)): XCTAssertEqual(candidates.count, 2)
        default: XCTFail("expected ambiguous, never pick the first")
        }
    }

    func testResolveOrg_matchesByFuzzyName() {
        // "Stakwrok" is a one-transposition typo of "Stakwork" — Levenshtein distance 2
        // (standard edit distance has no transposition special-case), within the
        // threshold (max(1, len/4) = 2 for an 8-char name) and not a substring either
        // way, so this only resolves via the Levenshtein pass, not exact/contains.
        let orgs = [org("1", login: "stakwork", name: "Stakwork")]
        let result = AIAgentManager.resolveOrg("Stakwrok", in: orgs)
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "1")
        default: XCTFail("expected fuzzy success")
        }
    }

    func testResolveOrg_fuzzyNameAmbiguousWhenClose() {
        // "Keta" is Levenshtein distance 1 from both "Beta" and "Zeta" — an exact tie,
        // not "clearly closer" (needs dist+2 <= next), so this must stay ambiguous
        // rather than silently picking one.
        let orgs = [org("1", login: "beta", name: "Beta"), org("2", login: "zeta", name: "Zeta")]
        let result = AIAgentManager.resolveOrg("Keta", in: orgs)
        switch result {
        case .failure(.ambiguous(let candidates)): XCTAssertEqual(candidates.count, 2)
        default: XCTFail("expected ambiguous")
        }
    }

    func testResolveOrg_unknownRef() {
        let orgs = [org("1", login: "acme", name: "Acme")]
        let result = AIAgentManager.resolveOrg("does-not-exist", in: orgs)
        switch result {
        case .failure(.unknown): break
        default: XCTFail("expected unknown")
        }
    }

    func testResolveOrg_emptyOrgList() {
        let result = AIAgentManager.resolveOrg(nil, in: [])
        switch result {
        case .failure(.noOrgs): break
        default: XCTFail("expected noOrgs")
        }
    }

    func testResolveOrg_resultAlwaysElementOfList() {
        let orgs = [org("1", login: "acme", name: "Acme"), org("2", login: "beta", name: "Beta")]
        guard case .success(let resolved) = AIAgentManager.resolveOrg("beta", in: orgs) else {
            XCTFail("expected success"); return
        }
        XCTAssertTrue(orgs.contains(where: { $0.id == resolved.id }))
    }

    // MARK: - HiveOrg Codable round-trip

    func testHiveOrg_codableRoundTrip() throws {
        let o = org("abc", login: "my-login", name: "My Org")
        let data = try JSONEncoder().encode(o)
        let decoded = try JSONDecoder().decode(HiveOrg.self, from: data)
        XCTAssertEqual(decoded, o)
    }

    // MARK: - cacheHiveOrgs / cachedHiveOrgs / defaultOrg

    func testCacheHiveOrgs_roundTrips() {
        let orgs = [org("1", login: "acme", name: "Acme"), org("2", login: "beta", name: "Beta")]
        AIAgentManager.cacheHiveOrgs(orgs)
        let cached = AIAgentManager.cachedHiveOrgs()
        XCTAssertEqual(cached.count, 2)
        XCTAssertEqual(Set(cached.map { $0.id }), Set(["1", "2"]))
    }

    func testDefaultOrg_singleOrg() {
        AIAgentManager.cacheHiveOrgs([org("1", login: "acme", name: "Acme")])
        XCTAssertEqual(AIAgentManager.defaultOrg?.id, "1")
    }

    func testDefaultOrg_multiOrgIsNil() {
        AIAgentManager.cacheHiveOrgs([org("1", login: "acme", name: "Acme"), org("2", login: "beta", name: "Beta")])
        XCTAssertNil(AIAgentManager.defaultOrg)
    }

    func testDefaultOrg_noOrgsIsNil() {
        AIAgentManager.cacheHiveOrgs([])
        XCTAssertNil(AIAgentManager.defaultOrg)
    }

    // MARK: - Pruning on org list refresh (indirect, via cache helpers)

    func testPruning_cachingFewerOrgsUpdatesTheOrgList() {
        // Seed org A + B caches directly (bypassing network fetch).
        let orgA = org("A", login: "org-a", name: "Org A")
        let orgB = org("B", login: "org-b", name: "Org B")
        AIAgentManager.cacheHiveOrgs([orgA, orgB])

        // Seed per-org slugs matching AIAgentManager.OrgSlugsEntry's shape.
        struct Entry: Codable { var slugs: [String]; var cachedAt: Double }
        let slugEntries: [String: Entry] = [
            "A": Entry(slugs: ["slug-a"], cachedAt: Date().timeIntervalSince1970),
            "B": Entry(slugs: ["slug-b"], cachedAt: Date().timeIntervalSince1970)
        ]
        if let encoded = try? JSONEncoder().encode(slugEntries) {
            UserDefaults.Keys.hiveOrgSlugsByOrg.set(encoded)
        }

        // Seed conversation ids
        let convDict = ["A": "conv-a", "B": "conv-b"]
        if let encoded = try? JSONEncoder().encode(convDict) {
            UserDefaults.Keys.hiveConversationIdByOrg.set(encoded)
        }

        // Seed canvas history
        let historyDict = ["A": historyWithProposal("p-a"), "B": historyWithProposal("p-b")]
        if let encoded = try? JSONEncoder().encode(historyDict) {
            UserDefaults.Keys.hiveCanvasChatHistoryByOrg.set(encoded)
        }

        // Seed a pending proposal belonging to org B
        let proposal = AIAgentManager.PendingProposal(
            proposalId: "p-b", kind: "feature", title: "T", description: nil,
            toolCallId: nil, rawInput: nil, orgId: "B", orgGithubLogin: "org-b"
        )
        if let encoded = try? JSONEncoder().encode(proposal) {
            UserDefaults.Keys.hivePendingProposal.set(encoded)
        }

        // Simulate a refresh that drops org B.
        AIAgentManager.cacheHiveOrgs([orgA])
        XCTAssertEqual(AIAgentManager.cachedHiveOrgs().map { $0.id }, ["A"])

        // Pruning itself (removing B's slugs/conversation/history/proposal) is the
        // private responsibility of fetchAndCacheHiveOrgs, which requires a network
        // round trip to exercise end-to-end; the resolution contract it depends on
        // (resolveProposalOrg refusing once an org leaves the cached list) is covered
        // by testResolveProposalOrg_pendingOrgIdNoLongerCached_isRefused above.
    }

    // MARK: - Canvas isolation

    func testCanvasHistory_unknownOrgReturnsEmpty() {
        let history = AIAgentManager.canvasHistory(orgId: "nonexistent-org")
        XCTAssertEqual(history.count, 0)
    }

    func testCanvasHistory_persistAndReadBackPerOrg() {
        let historyA = [AIAgentManager.CanvasChatMessage(role: "user", content: "question for A")]
        let historyB = [AIAgentManager.CanvasChatMessage(role: "user", content: "question for B")]

        AIAgentManager.persistCanvasHistory(historyA, orgId: "org-a")
        AIAgentManager.persistCanvasHistory(historyB, orgId: "org-b")

        let readA = AIAgentManager.canvasHistory(orgId: "org-a")
        let readB = AIAgentManager.canvasHistory(orgId: "org-b")

        XCTAssertEqual(readA.count, 1)
        XCTAssertEqual(readA.first?.content, "question for A")
        XCTAssertEqual(readB.count, 1)
        XCTAssertEqual(readB.first?.content, "question for B")
    }

    func testCanvasHistory_queryOrgBThenApproveOrgAProposal_leavesHistoriesIsolated() {
        // Org A already has a turn persisted (simulating an earlier query).
        let historyA = [
            AIAgentManager.CanvasChatMessage(role: "user", content: "A q1"),
            AIAgentManager.CanvasChatMessage(role: "assistant", content: "A a1")
        ]
        AIAgentManager.persistCanvasHistory(historyA, orgId: "org-a")

        // Simulate a query to org B appending a new turn.
        var historyB = AIAgentManager.canvasHistory(orgId: "org-b")
        historyB.append(AIAgentManager.CanvasChatMessage(role: "user", content: "B q1"))
        historyB.append(AIAgentManager.CanvasChatMessage(role: "assistant", content: "B a1"))
        AIAgentManager.persistCanvasHistory(historyB, orgId: "org-b")

        // Org A's history must be untouched by the org B query.
        let readA = AIAgentManager.canvasHistory(orgId: "org-a")
        XCTAssertEqual(readA.count, 2)
        XCTAssertEqual(readA.map { $0.content }, ["A q1", "A a1"])

        // Org B's history only contains B's turns.
        let readB = AIAgentManager.canvasHistory(orgId: "org-b")
        XCTAssertEqual(readB.count, 2)
        XCTAssertEqual(readB.map { $0.content }, ["B q1", "B a1"])
    }

    // MARK: - resolveProposalOrg

    func testResolveProposalOrg_pendingWithOrgId() {
        let orgA = org("org-a", login: "a-login", name: "A")
        AIAgentManager.cacheHiveOrgs([orgA])
        AIAgentManager.sharedInstance.pendingProposal = AIAgentManager.PendingProposal(
            proposalId: "p1", kind: "feature", title: "T", description: nil,
            toolCallId: nil, rawInput: nil, orgId: "org-a", orgGithubLogin: "a-login"
        )
        let result = AIAgentManager.resolveProposalOrg(proposalId: "p1")
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "org-a")
        default: XCTFail("expected success")
        }
    }

    func testResolveProposalOrg_pendingOrgIdNoLongerCached_isRefused() {
        AIAgentManager.cacheHiveOrgs([org("org-b", login: "b-login", name: "B")])
        AIAgentManager.sharedInstance.pendingProposal = AIAgentManager.PendingProposal(
            proposalId: "p1", kind: "feature", title: "T", description: nil,
            toolCallId: nil, rawInput: nil, orgId: "org-a", orgGithubLogin: "a-login"
        )
        let result = AIAgentManager.resolveProposalOrg(proposalId: "p1")
        switch result {
        case .failure(.notFound): break
        default: XCTFail("expected refusal — org left the list")
        }
    }

    func testResolveProposalOrg_historyOnlyFoundInExactlyOneOrg() {
        let orgA = org("org-a", login: "a-login", name: "A")
        let orgB = org("org-b", login: "b-login", name: "B")
        AIAgentManager.cacheHiveOrgs([orgA, orgB])

        AIAgentManager.persistCanvasHistory(historyWithProposal("p-unique"), orgId: "org-a")
        AIAgentManager.persistCanvasHistory([], orgId: "org-b")

        let result = AIAgentManager.resolveProposalOrg(proposalId: "p-unique")
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "org-a")
        default: XCTFail("expected success")
        }
    }

    func testResolveProposalOrg_foundInTwoOrgsIsRefused() {
        let orgA = org("org-a", login: "a-login", name: "A")
        let orgB = org("org-b", login: "b-login", name: "B")
        AIAgentManager.cacheHiveOrgs([orgA, orgB])

        AIAgentManager.persistCanvasHistory(historyWithProposal("p-dup"), orgId: "org-a")
        AIAgentManager.persistCanvasHistory(historyWithProposal("p-dup"), orgId: "org-b")

        let result = AIAgentManager.resolveProposalOrg(proposalId: "p-dup")
        switch result {
        case .failure(.notFound): break
        default: XCTFail("expected refusal — found in two orgs")
        }
    }

    func testResolveProposalOrg_foundInNoneIsRefused() {
        AIAgentManager.cacheHiveOrgs([org("org-a", login: "a-login", name: "A")])
        let result = AIAgentManager.resolveProposalOrg(proposalId: "p-missing")
        switch result {
        case .failure(.notFound): break
        default: XCTFail("expected refusal")
        }
    }

    func testResolveProposalOrg_legacyProposalNoOrgId_singleOrgResolves() {
        let orgA = org("org-a", login: "a-login", name: "A")
        AIAgentManager.cacheHiveOrgs([orgA])
        AIAgentManager.sharedInstance.pendingProposal = AIAgentManager.PendingProposal(
            proposalId: "legacy-1", kind: "feature", title: "T", description: nil,
            toolCallId: nil, rawInput: nil, orgId: nil, orgGithubLogin: nil
        )
        let result = AIAgentManager.resolveProposalOrg(proposalId: "legacy-1")
        switch result {
        case .success(let o): XCTAssertEqual(o.id, "org-a")
        default: XCTFail("expected success via defaultOrg fallback")
        }
    }

    func testResolveProposalOrg_legacyProposalNoOrgId_multiOrgIsRefused() {
        AIAgentManager.cacheHiveOrgs([org("org-a", login: "a", name: "A"), org("org-b", login: "b", name: "B")])
        AIAgentManager.sharedInstance.pendingProposal = AIAgentManager.PendingProposal(
            proposalId: "legacy-2", kind: "feature", title: "T", description: nil,
            toolCallId: nil, rawInput: nil, orgId: nil, orgGithubLogin: nil
        )
        let result = AIAgentManager.resolveProposalOrg(proposalId: "legacy-2")
        switch result {
        case .failure(.notFound): break
        default: XCTFail("expected refusal — ambiguous across multiple orgs")
        }
    }

    func testResolveProposalOrg_legacyJSONDecodesWithNilOrgFields() throws {
        // Simulate a proposal persisted before multi-org support (JSON without orgId/orgGithubLogin).
        let legacyJSON = """
        {"proposalId":"old-1","kind":"feature","title":"Old","description":null,"toolCallId":null,"rawInput":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AIAgentManager.PendingProposal.self, from: legacyJSON)
        XCTAssertNil(decoded.orgId)
        XCTAssertNil(decoded.orgGithubLogin)
        XCTAssertEqual(decoded.proposalId, "old-1")
    }

    // MARK: - Prompt sanitization
    //
    // Exercised directly against `AIAgentManager.sanitizeForPrompt`, the helper
    // `buildQueryHiveGraphTool(ownerNickname:orgs:)` uses to build its data-only
    // [ORGS] block — this avoids depending on the shape of the third-party
    // `TypedTool` type (e.g. whether `.description` is itself public/stable).

    func testSanitizeForPrompt_stripsNewlinesAndControlCharacters() {
        let input = "Name\nwith\nnewlines  and \t tabs\r\nhere"
        let out = AIAgentManager.sanitizeForPrompt(input, maxLength: 200)
        XCTAssertFalse(out.contains("\n"))
        XCTAssertFalse(out.contains("\r"))
        XCTAssertFalse(out.contains("\t"))
        // Still a single collapsed-whitespace line containing the original words.
        XCTAssertTrue(out.contains("Name"))
        XCTAssertTrue(out.contains("newlines"))
        XCTAssertTrue(out.contains("tabs"))
        XCTAssertTrue(out.contains("here"))
        XCTAssertFalse(out.contains("  "), "whitespace should be collapsed to single spaces")
    }

    func testSanitizeForPrompt_collapsesWhitespace() {
        let input = "a    b     c"
        let out = AIAgentManager.sanitizeForPrompt(input, maxLength: 200)
        XCTAssertEqual(out, "a b c")
    }

    func testSanitizeForPrompt_capsLength() {
        let input = String(repeating: "A", count: 100)
        let out = AIAgentManager.sanitizeForPrompt(input, maxLength: 64)
        XCTAssertEqual(out.count, 64)
    }

    func testSanitizeForPrompt_shortStringUnaffected() {
        let out = AIAgentManager.sanitizeForPrompt("login-one", maxLength: 39)
        XCTAssertEqual(out, "login-one")
    }

    func testSanitizeForPrompt_combinedControlCharsAndOverLength_singleTruncatedLine() {
        let longWithControlChars = "Org\nName\t" + String(repeating: "Z", count: 100)
        let out = AIAgentManager.sanitizeForPrompt(longWithControlChars, maxLength: 64)
        XCTAssertFalse(out.contains("\n"))
        XCTAssertFalse(out.contains("\t"))
        XCTAssertLessThanOrEqual(out.count, 64)
    }

    // MARK: - Concurrency

    func testConcurrentCacheWrites_allSurviveForDifferentOrgIds() {
        let iterations = 50
        let expectation = self.expectation(description: "concurrent writes complete")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let orgId = "org-\(i)"
            AIAgentManager.persistCanvasHistory(
                [AIAgentManager.CanvasChatMessage(role: "user", content: "msg-\(i)")],
                orgId: orgId
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10)

        for i in 0..<iterations {
            let history = AIAgentManager.canvasHistory(orgId: "org-\(i)")
            XCTAssertEqual(history.count, 1, "org-\(i) should have survived concurrent writes")
            XCTAssertEqual(history.first?.content, "msg-\(i)")
        }
    }
}
