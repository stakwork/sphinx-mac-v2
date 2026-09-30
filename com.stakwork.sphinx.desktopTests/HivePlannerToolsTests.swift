//
//  HivePlannerToolsTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  NOTE: All JSON fixtures in this file are PROVISIONAL (hand-written); they
//  have not been verified against real Hive responses. FORM / PLAN artifact
//  shapes in particular are unconfirmed.
//
//  No test here touches Alamofire (AF) or API.sharedInstance.
//

import XCTest
import SwiftyJSON
@testable import com_stakwork_sphinx_desktop

typealias Mgr = AIAgentManager

final class HivePlannerToolsTests: XCTestCase {

    // MARK: - Helpers

    private func j(_ s: String) -> JSON { JSON(parseJSON: s) }

    // MARK: - formatPlan

    func testFormatPlan_full() {
        let json = j("""
        {"data":{"title":"Login","brief":"Let users log in","userStories":[{"title":"As a user I log in"},{"title":"As admin I reset"}],
        "requirements":"Must use OAuth","architecture":"Service X","workflowStatus":"COMPLETED"}}
        """)
        let out = Mgr.formatPlan(json: json, fallbackTitle: "fb")
        XCTAssertTrue(out.contains("Login"))
        XCTAssertTrue(out.contains("Let users log in"))
        XCTAssertTrue(out.contains("As a user I log in"))
        XCTAssertTrue(out.contains("As admin I reset"))
        XCTAssertTrue(out.contains("Must use OAuth"))
        XCTAssertTrue(out.contains("Service X"))
        XCTAssertTrue(out.contains("Workflow Status: COMPLETED"))
        XCTAssertFalse(out.contains("(not written yet)"))
    }

    func testFormatPlan_emptySections() {
        let out = Mgr.formatPlan(json: j(#"{"data":{"title":"T"}}"#), fallbackTitle: "fb")
        XCTAssertEqual(out.components(separatedBy: "(not written yet)").count - 1, 4)
        XCTAssertTrue(out.contains("Workflow Status: none"))
    }

    func testFormatPlan_userStoriesAsStrings() {
        let out = Mgr.formatPlan(json: j(#"{"data":{"userStories":["story one","story two"]}}"#), fallbackTitle: "fb")
        XCTAssertTrue(out.contains("- story one"))
        XCTAssertTrue(out.contains("- story two"))
    }

    func testFormatPlan_userStoriesAsObjects() {
        let out = Mgr.formatPlan(json: j(#"{"data":{"userStories":[{"title":"obj story"}]}}"#), fallbackTitle: "fb")
        XCTAssertTrue(out.contains("- obj story"))
    }

    func testFormatPlan_failure() {
        XCTAssertTrue(Mgr.formatPlan(json: nil, fallbackTitle: "Feat").contains("Failed"))
        XCTAssertTrue(Mgr.formatPlan(json: j(#"{"error":"nope"}"#), fallbackTitle: "Feat").contains("Failed"))
        XCTAssertTrue(Mgr.formatPlan(json: j(#"{"success":false}"#), fallbackTitle: "Feat").contains("Failed"))
    }

    // MARK: - formatChat / summariseArtifact

    func testFormatChat_empty() {
        XCTAssertEqual(Mgr.formatChat(messages: []), "No planner messages yet")
    }

    func testFormatChat_roleLowercased() {
        let out = Mgr.formatChat(messages: [j(#"{"role":"ASSISTANT","message":"hello"}"#), j(#"{"role":"USER","message":"hi"}"#)])
        XCTAssertTrue(out.contains("[assistant] hello"))
        XCTAssertTrue(out.contains("[user] hi"))
    }

    func testSummariseArtifact_planFormAndUnknown() {
        let plan = Mgr.summariseArtifact(j(#"{"type":"PLAN","content":{"brief":"b"}}"#))
        XCTAssertTrue(plan.contains("PLAN"))
        XCTAssertTrue(plan.contains("brief"))
        let form = Mgr.summariseArtifact(j(#"{"type":"FORM","content":{"fields":["a"]}}"#))
        XCTAssertTrue(form.contains("FORM"))
        let unknown = Mgr.summariseArtifact(j(#"{"content":"x"}"#))
        XCTAssertTrue(unknown.contains("UNKNOWN"))
    }

    func testSummariseArtifact_truncates() {
        let long = String(repeating: "a", count: 500)
        let out = Mgr.summariseArtifact(j(#"{"type":"PLAN","content":""# + long + #""}"#))
        XCTAssertTrue(out.hasSuffix("…"))
        XCTAssertFalse(out.contains(String(repeating: "a", count: 201)))
    }

    func testFormatChat_artifactLines() {
        let out = Mgr.formatChat(messages: [j(#"{"role":"ASSISTANT","message":"see","artifacts":[{"type":"FORM","content":"c"}]}"#)])
        XCTAssertTrue(out.contains("[assistant] see"))
        XCTAssertTrue(out.contains("[artifact FORM]"))
    }

    func testFormatChat_last30Window() {
        let msgs = (0..<40).map { j(#"{"role":"USER","message":"m\#($0)x"}"#) }
        let out = Mgr.formatChat(messages: msgs)
        XCTAssertFalse(out.contains("m9x"))
        XCTAssertTrue(out.contains("m10x"))
        XCTAssertTrue(out.contains("m39x"))
        XCTAssertEqual(out.components(separatedBy: "\n").count, 30)
    }

    // MARK: - formatFeatureDetail

    func testFormatFeatureDetail_dataWrapper() {
        let json = j("""
        {"success":true,"data":{"title":"Feat","status":"IN_PROGRESS","priority":"HIGH","description":"desc",
        "workflowStatus":"COMPLETED","deploymentStatus":"PRODUCTION","deploymentUrl":"https://x.dev",
        "createdAt":"c","updatedAt":"u","tasks":[{},{}]}}
        """)
        let out = Mgr.formatFeatureDetail(json: json, featureId: "id1", fallbackTitle: "fb")
        XCTAssertTrue(out.contains("Feature: Feat"))
        XCTAssertTrue(out.contains("Status: IN_PROGRESS"))
        XCTAssertTrue(out.contains("Priority: HIGH"))
        XCTAssertTrue(out.contains("Description: desc"))
        XCTAssertTrue(out.contains("Workflow Status: COMPLETED"))
        XCTAssertTrue(out.contains("Deployment Status: PRODUCTION"))
        XCTAssertTrue(out.contains("Deployment URL: https://x.dev"))
        XCTAssertTrue(out.contains("Created: c"))
        XCTAssertTrue(out.contains("Updated: u"))
        XCTAssertTrue(out.contains("Tasks: 2"))
    }

    func testFormatFeatureDetail_topLevelFallback() {
        let out = Mgr.formatFeatureDetail(json: j(#"{"title":"Top","status":"NEW"}"#), featureId: "id1", fallbackTitle: "fb")
        XCTAssertTrue(out.contains("Feature: Top"))
        XCTAssertTrue(out.contains("Status: NEW"))
    }

    func testFormatFeatureDetail_none() {
        let out = Mgr.formatFeatureDetail(json: j(#"{"data":{"title":"T"}}"#), featureId: "id1", fallbackTitle: "fb")
        XCTAssertTrue(out.contains("Workflow Status: none"))
        XCTAssertTrue(out.contains("Deployment Status: none"))
    }

    func testFormatFeatureDetail_urlOnlyIfPresent() {
        let without = Mgr.formatFeatureDetail(json: j(#"{"data":{"title":"T"}}"#), featureId: "id1", fallbackTitle: "fb")
        XCTAssertFalse(without.contains("Deployment URL"))
        let empty = Mgr.formatFeatureDetail(json: j(#"{"data":{"title":"T","deploymentUrl":""}}"#), featureId: "id1", fallbackTitle: "fb")
        XCTAssertFalse(empty.contains("Deployment URL"))
    }

    func testFormatFeatureDetail_failures() {
        XCTAssertTrue(Mgr.formatFeatureDetail(json: nil, featureId: "i", fallbackTitle: "F").contains("Failed to fetch detail for feature"))
        XCTAssertTrue(Mgr.formatFeatureDetail(json: j(#"{"error":"x"}"#), featureId: "i", fallbackTitle: "F").contains("Failed to fetch detail for feature"))
        XCTAssertTrue(Mgr.formatFeatureDetail(json: j(#"{"success":false,"data":{"title":"T"}}"#), featureId: "i", fallbackTitle: "F").contains("Failed to fetch detail for feature"))
    }

    // MARK: - HiveWriteResult.from

    func testWriteResult_success() {
        let r = HiveWriteResult.from(statusCode: 200, json: j(#"{"success":true}"#), transportError: nil)
        if case .success = r {} else { XCTFail("expected success, got \(r)") }
    }

    func testWriteResult_200SuccessFalse() {
        let r = HiveWriteResult.from(statusCode: 200, json: j(#"{"success":false}"#), transportError: nil)
        if case .failed = r {} else { XCTFail("expected failed, got \(r)") }
    }

    func testWriteResult_200ErrorField() {
        let r = HiveWriteResult.from(statusCode: 200, json: j(#"{"success":true,"error":"boom"}"#), transportError: nil)
        XCTAssertEqual(r, .failed("boom"))
    }

    func testWriteResult_statusMapping() {
        XCTAssertEqual(HiveWriteResult.from(statusCode: 401, json: nil, transportError: nil), .unauthorized)
        XCTAssertEqual(HiveWriteResult.from(statusCode: 403, json: nil, transportError: nil), .forbidden)
        XCTAssertEqual(HiveWriteResult.from(statusCode: 404, json: nil, transportError: nil), .notFound)
        XCTAssertEqual(HiveWriteResult.from(statusCode: 409, json: j(#"{"error":"busy"}"#), transportError: nil), .conflict("busy"))
        XCTAssertEqual(HiveWriteResult.from(statusCode: 409, json: nil, transportError: nil), .conflict(""))
        XCTAssertEqual(HiveWriteResult.from(statusCode: 500, json: nil, transportError: nil), .failed("HTTP 500"))
    }

    func testWriteResult_timeoutIsUnknownOutcome() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(HiveWriteResult.from(statusCode: nil, json: nil, transportError: err), .unknownOutcome)
    }

    // MARK: - performHiveWrite

    private final class Counter: @unchecked Sendable {
        // Test-only: all closures run synchronously on the calling thread.
        var sends = 0
        var reauths = 0
        var tokens: [String] = []
    }

    private func runWrite(
        responses: [(Int?, Data?, Error?)],
        reauthToken: String? = "new"
    ) -> (HiveWriteResult, Counter) {
        let c = Counter()
        var result: HiveWriteResult?
        API.performHiveWrite(
            token: "old",
            build: { token in
                c.tokens.append(token)
                return URLRequest(url: URL(string: "https://example.test/x")!)
            },
            reauth: { done in c.reauths += 1; done(reauthToken) },
            send: { _, done in
                let idx = min(c.sends, responses.count - 1)
                c.sends += 1
                let r = responses[idx]
                done(r.0, r.1, r.2)
            },
            completion: { result = $0 }
        )
        return (result ?? .failed("no completion"), c)
    }

    private let okData = Data(#"{"success":true}"#.utf8)

    func testPerformWrite_401ThenSuccess_reauthsOnceRetriesOnce() {
        let (r, c) = runWrite(responses: [(401, nil, nil), (200, okData, nil)])
        if case .success = r {} else { XCTFail("got \(r)") }
        XCTAssertEqual(c.sends, 2)
        XCTAssertEqual(c.reauths, 1)
        XCTAssertEqual(c.tokens, ["old", "new"])
    }

    func testPerformWrite_401Twice_unauthorized() {
        let (r, c) = runWrite(responses: [(401, nil, nil), (401, nil, nil)])
        XCTAssertEqual(r, .unauthorized)
        XCTAssertEqual(c.sends, 2)
        XCTAssertEqual(c.reauths, 1)
    }

    func testPerformWrite_409_noRetry() {
        let (r, c) = runWrite(responses: [(409, Data(#"{"error":"busy"}"#.utf8), nil)])
        XCTAssertEqual(r, .conflict("busy"))
        XCTAssertEqual(c.sends, 1)
        XCTAssertEqual(c.reauths, 0)
    }

    func testPerformWrite_403_noRetry() {
        let (r, c) = runWrite(responses: [(403, nil, nil)])
        XCTAssertEqual(r, .forbidden)
        XCTAssertEqual(c.sends, 1)
        XCTAssertEqual(c.reauths, 0)
    }

    func testPerformWrite_transportError_noRetry() {
        let err = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let (r, c) = runWrite(responses: [(nil, nil, err)])
        XCTAssertEqual(r, .unknownOutcome)
        XCTAssertEqual(c.sends, 1)
        XCTAssertEqual(c.reauths, 0)
    }

    // MARK: - buildFeatureChatSendRequest

    func testBuildRequest_bodyAndNulls() throws {
        let req = try XCTUnwrap(API.buildFeatureChatSendRequest(featureId: "abc", message: "hi", replyId: nil, token: "tok"))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = try XCTUnwrap(req.httpBody)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["message"] as? String, "hi")
        XCTAssertTrue(obj["replyId"] is NSNull)
        XCTAssertTrue(obj["sourceWebsocketID"] is NSNull)
        XCTAssertEqual((obj["contextTags"] as? [Any])?.count, 0)
        XCTAssertEqual((obj["selectedRepositoryIds"] as? [Any])?.count, 0)
    }

    func testBuildRequest_replyIdSet() throws {
        let req = try XCTUnwrap(API.buildFeatureChatSendRequest(featureId: "abc", message: "hi", replyId: "r1", token: "t"))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(req.httpBody)) as? [String: Any])
        XCTAssertEqual(obj["replyId"] as? String, "r1")
    }

    func testBuildRequest_percentEncodesId() throws {
        let req = try XCTUnwrap(API.buildFeatureChatSendRequest(featureId: "a/b c", message: "m", replyId: nil, token: "t"))
        let url = try XCTUnwrap(req.url?.absoluteString)
        XCTAssertTrue(url.hasSuffix("/features/a%2Fb%20c/chat"), url)
    }

    // MARK: - sendToPlanner

    private final class SendSpy: @unchecked Sendable {
        // Test-only: used from a single async test context.
        var sends = 0
        var result: HiveWriteResult
        init(_ result: HiveWriteResult) { self.result = result }
    }

    private func runSend(detail: JSON?, result: HiveWriteResult = .success(JSON(["success": true]))) async -> (String, SendSpy) {
        let spy = SendSpy(result)
        let out = await Mgr.sendToPlanner(
            featureId: "f1",
            message: "hello",
            replyId: nil,
            fetchDetail: { _ in detail },
            send: { _, _, _ in spy.sends += 1; return spy.result }
        )
        return (out, spy)
    }

    func testSendToPlanner_inProgressNeverSends() async {
        let (out, spy) = await runSend(detail: j(#"{"data":{"workflowStatus":"IN_PROGRESS"}}"#))
        XCTAssertEqual(out, Mgr.plannerBusyMessage)
        XCTAssertEqual(spy.sends, 0)
    }

    func testSendToPlanner_nilDetailNeverSends() async {
        let (out, spy) = await runSend(detail: nil)
        XCTAssertTrue(out.contains("Nothing was sent"))
        XCTAssertEqual(spy.sends, 0)
    }

    func testSendToPlanner_detailWithoutDataObjectNeverSends() async {
        let (out, spy) = await runSend(detail: j(#"{"title":"T","workflowStatus":"COMPLETED"}"#))
        XCTAssertTrue(out.contains("Nothing was sent"))
        XCTAssertEqual(spy.sends, 0)
        let (_, spy2) = await runSend(detail: j(#"{"success":false,"data":{"title":"T"}}"#))
        XCTAssertEqual(spy2.sends, 0)
    }

    func testSendToPlanner_conflictIsBusy() async {
        let (out, spy) = await runSend(detail: j(#"{"data":{"workflowStatus":"COMPLETED"}}"#), result: .conflict("x"))
        XCTAssertEqual(out, Mgr.plannerBusyMessage)
        XCTAssertEqual(spy.sends, 1)
    }

    func testSendToPlanner_success() async {
        let (out, spy) = await runSend(detail: j(#"{"data":{"workflowStatus":"COMPLETED"}}"#))
        XCTAssertEqual(out, "Message sent to the planner.")
        XCTAssertEqual(spy.sends, 1)
    }

    func testSendToPlanner_unknownOutcomeWarnsNoResend() async {
        let (out, spy) = await runSend(detail: j(#"{"data":{}}"#), result: .unknownOutcome)
        XCTAssertTrue(out.contains("do NOT resend"))
        XCTAssertEqual(spy.sends, 1)
    }

    // MARK: - resolveFeature

    private func page(_ titles: [(String, String)], hasMore: Bool) -> JSON {
        JSON([
            "data": titles.map { ["id": $0.0, "title": $0.1] },
            "hasMore": hasMore
        ] as [String: Any])
    }

    func testResolveFeature_matchOnPage2() async {
        let res = await Mgr.resolveFeature(featureName: "Payments") { p in
            p == 1 ? self.page([("a", "Alpha")], hasMore: true)
                   : self.page([("b", "Payments")], hasMore: false)
        }
        XCTAssertEqual(res, .found(id: "b", title: "Payments"))
    }

    func testResolveFeature_stopsAtCap() async {
        var calls = 0
        let res = await Mgr.resolveFeature(featureName: "zzzzzzzzzz", cap: 3) { _ in
            calls += 1
            return self.page([("a", "Alpha")], hasMore: true)
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(res, .message("No feature found matching 'zzzzzzzzzz' (not found in 3 page(s))."))
    }
}
