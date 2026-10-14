//
//  AIAgentManager+GraphRecall.swift
//  sphinx
//
//  The agent reads what extraction stored: a passive summary appended to the system prompt
//  each turn, and the recall_personal_knowledge tool. Always on (graphExtractionEnabled gates
//  only extraction). See docs/graph-recall.md.
//
import Foundation
import SwiftAISDK

extension AIAgentManager {

    /// Per-turn graph section to append AFTER the constant system prompt; "" when the graph is
    /// empty, unavailable, slow or fails. Never throws and never blocks longer than the timeout.
    func graphSummarySection() async -> String {
        return await GraphRecall.summarySection(from: PersonalGraph.service) ?? ""
    }

    func buildRecallPersonalKnowledgeTool() -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "hops": .object(["type": .string("integer")])
                ]),
                "required": .array([.string("query")])
            ]))
        )
        return tool(
            description: """
                Look up what you remember about the user's own people, places, things and topics \
                (e.g. "my sister", "where I live", "Alice", "Paris"). Use it for questions about the \
                user's own life or contacts outside Sphinx, before saying you don't know. \
                Takes query (a name or alias; exact matches first, then partial matches) and optional \
                hops (1 or 2, default 1; 2 also returns relations of related items). Returns matching \
                items with their relations as short text. This is the user's remembered personal \
                knowledge, not their Sphinx contacts or chats.
                """,
            inputSchema: inputSchema,
            execute: { (input: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                var query = ""
                var hops: Int? = nil
                if case .object(let dict) = input {
                    if case .string(let s) = dict["query"] { query = s }
                    if case .number(let n) = dict["hops"], n.isFinite { hops = Int(max(min(n, 100), -100)) }
                }
                let output = await GraphRecall.toolOutput(query: query, hops: hops, source: PersonalGraph.service)
                print("AIAgent recall_personal_knowledge: returning \(output.count) chars")
                return .value(.string(output))
            }
        )
    }
}
