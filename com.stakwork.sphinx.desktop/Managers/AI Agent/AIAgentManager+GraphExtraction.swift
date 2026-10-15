//
//  AIAgentManager+GraphExtraction.swift
//  sphinx
//
//  After an agent turn finished and the answer was returned, a fire-and-forget
//  background task makes a SECOND model call (same model, NO tools) that extracts
//  personal knowledge, and writes it as one batch through GraphJournalService.apply().
//  The user never waits for it. See docs/graph-extraction.md.
//
import Foundation
import SwiftAISDK

extension AIAgentManager {

    /// `model` is the model `chat()` already resolved from the user's provider settings.
    func scheduleGraphExtraction(
        model: any LanguageModelV3,
        userText: String,
        assistantText: String,
        toolNames: [String],
        didFail: Bool
    ) {
        guard GraphExtractionPolicy.shouldExtract(userText: userText, toolNames: toolNames, didFail: didFail) else {
            return
        }
        // Privacy switch: checked BEFORE the extraction model call.
        guard GraphExtractionSettings.isEnabled() else { return }
        guard let graph = PersonalGraph.service else { return }

        Task.detached(priority: .utility) {
            await AIAgentManager.runGraphExtraction(
                model: model,
                graph: graph,
                userText: userText,
                assistantText: assistantText
            )
        }
    }

    private static func runGraphExtraction(
        model: any LanguageModelV3,
        graph: GraphJournalService,
        userText: String,
        assistantText: String
    ) async {
        do {
            let result: any GenerateTextResult = try await generateText(
                model: model,
                system: GraphExtractionPrompt.system,
                messages: [.user(GraphExtractionPrompt.userPrompt(userText: userText, assistantText: assistantText))]
            )

            switch GraphExtractionParser.parse(result.text) {
            case .empty:
                return
            case .invalid(let reason):
                print("AIAgent graph extraction: dropped invalid result – \(reason)")
            case .valid(let extraction):
                let snapshot = try await graph.storeSnapshot()
                let operations = try GraphExtractionOperations.operations(for: extraction, existing: snapshot)
                guard !operations.isEmpty else { return }
                try await graph.apply(operations)
            }
        } catch {
            print("AIAgent graph extraction failed – \(error)")
        }
    }
}
