//
//  AIAgentManager.swift
//  sphinx
//
//  Created by Sphinx on 31/03/2026.
//  Copyright © 2026 sphinx. All rights reserved.
//

import Foundation
import SwiftAISDK
import AnthropicProvider
import OpenAIProvider

// MARK: - Codable wrapper for history persistence
struct AIAgentMessage: Codable {
    let role: String   // "user" or "assistant"
    let text: String
}

final class AIAgentManager: @unchecked Sendable {

    static let sharedInstance = AIAgentManager()
    static let agentLocalId: Int = -2

    // MARK: - Provider enum

    enum AIProvider: String, CaseIterable {
        case anthropic = "Anthropic"
        case openAI    = "OpenAI"
    }

    // MARK: - State

    var conversationHistory: [ModelMessage] = []
    var lastIncomingMessageDate: Date? = nil
    private var lastCheckedIncomingDate: Date? = nil

    /// The currently active language model (nil if not configured)
    private var activeModel: (any LanguageModelV3)?

    /// Tavily API key for web search (nil or empty = tool not registered)
    private var tavilyApiKey: String? = nil

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a helpful AI assistant embedded inside the Sphinx messaging app on macOS.
    You can interact with the user's Sphinx contacts and chats using the following tools:

    - send_sphinx_message: Send a message to one of the user's Sphinx contacts or tribes by name. \
    IMPORTANT: Before invoking this tool, you MUST describe exactly what you are about to do \
    (contact name and message text) and ask the user for explicit confirmation (e.g. "Shall I send this?"). \
    Only invoke the tool after the user confirms.

    - read_recent_messages: Read recent messages from a conversation with a specific contact or tribe. \
    Use this to look up what was said in a chat.

    - web_search: Search the internet for current events, facts, or any topic requiring \
    up-to-date information. Use this whenever the user asks about recent news, prices, \
    people, or anything you may not know. Present results clearly with titles and URLs.

    CRITICAL TOOL RESULT RULES:
    - Tool results that start with "Message sent successfully" mean the message was delivered. \
    Always report this as a success. Do NOT say there was an error or that you're unsure.
    - Tool results that start with "Send failed" or "No contact" or "No tribe" mean genuine failure.
    - When read_recent_messages returns a list of messages, present them clearly to the user. \
    Do NOT say there was a format issue or that you couldn't read them.
    - Never assume failure unless the tool result explicitly contains the word "failed" or "error".
    - When web_search returns results, present them clearly with titles, snippets, and URLs. Never say you cannot search the web.

    Always be concise and helpful. When you're unsure about a contact's name, ask for clarification.
    """

    // MARK: - History persistence

    private var historyDefaultsKey: String {
        "\(UserData.sharedInstance.accountUUID).aiAgentHistory"
    }

    /// Append an assistant message directly (used for intro message persistence)
    func appendAssistantMessage(_ text: String) {
        conversationHistory.append(.assistant(text))
        saveHistory()
    }

    // MARK: - History persistence (private)

    private func saveHistory() {
        let wrapped: [AIAgentMessage] = conversationHistory.compactMap { msg in
            switch msg {
            case .user(let userMsg):
                if case .text(let t) = userMsg.content { return AIAgentMessage(role: "user", text: t) }
                return nil
            case .assistant(let assistantMsg):
                if case .text(let t) = assistantMsg.content { return AIAgentMessage(role: "assistant", text: t) }
                return nil
            default:
                return nil
            }
        }
        if let data = try? JSONEncoder().encode(wrapped) {
            UserDefaults.standard.set(data, forKey: historyDefaultsKey)
        }
    }

    func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
              let wrapped = try? JSONDecoder().decode([AIAgentMessage].self, from: data) else { return }
        conversationHistory = wrapped.compactMap { msg in
            switch msg.role {
            case "user":      return .user(msg.text)
            case "assistant": return .assistant(msg.text)
            default: return nil
            }
        }
    }

    // MARK: - Init

    private init() {
        observeIncomingMessages()
        reconfigure()
        loadHistory()
    }

    // MARK: - Reconfigure

    /// Call this after saving new provider / key settings in the profile.
    func reconfigure() {
        let userData = UserData.sharedInstance
        let providerRaw = userData.getAIAgentValue(with: .aiAgentProvider) ?? ""
        let apiKey      = userData.getAIAgentValue(with: .aiAgentApiKey)   ?? ""
        let provider    = AIProvider(rawValue: providerRaw) ?? .anthropic

        // Load search key independently (optional, not gated on LLM key)
        tavilyApiKey = userData.getAIAgentValue(with: .aiAgentSearchApiKey)

        guard !apiKey.isEmpty else {
            activeModel = nil
            return
        }

        switch provider {
        case .anthropic:
            let p = createAnthropicProvider(settings: AnthropicProviderSettings(apiKey: apiKey))
            activeModel = p.chat(modelId: "claude-sonnet-4-6")
        case .openAI:
            let p = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: apiKey))
            activeModel = p.chat(modelId: "gpt-4o")
        }

        // Reset history when credentials change
        reset()

        // Create agent contact + chat if not already present
        Task { @MainActor in
            self.createAgentContactAndChatIfNeeded()
        }
    }

    // MARK: - Agent Contact + Chat Creation

    @MainActor
    func createAgentContactAndChatIfNeeded() {
        guard activeModel != nil, let owner = UserContact.getOwner() else { return }
        guard UserContact.getContactWith(id: AIAgentManager.agentLocalId) == nil else { return }

        let context = CoreDataManager.sharedManager.persistentContainer.viewContext

        // Create the agent UserContact
        let agentContact = UserContact(context: context)
        agentContact.id = AIAgentManager.agentLocalId
        agentContact.nickname = "Sphinx Agent"
        agentContact.isAgent = true
        agentContact.isOwner = false
        agentContact.fromGroup = false
        agentContact.status = UserContact.Status.Confirmed.rawValue
        agentContact.publicKey = ""
        agentContact.createdAt = Date()

        // Create the local Chat
        _ = Chat.createObject(
            id: AIAgentManager.agentLocalId,
            name: "Sphinx Agent",
            photoUrl: nil,
            uuid: nil,
            type: Chat.ChatType.conversation.rawValue,
            status: Chat.ChatStatus.approved.rawValue,
            muted: false,
            seen: true,
            host: nil,
            groupKey: nil,
            ownerPubkey: nil,
            pricePerMessage: 0,
            escrowAmount: 0,
            myAlias: nil,
            myPhotoUrl: nil,
            notify: 0,
            pinnedMessageUUID: nil,
            contactIds: [NSNumber(value: owner.id), NSNumber(value: AIAgentManager.agentLocalId)],
            pendingContactIds: [],
            date: Date(),
            metaData: nil
        )

        CoreDataManager.sharedManager.saveContext()

        NotificationCenter.default.post(name: .onContactsAndChatsChanged, object: nil)
    }

    // MARK: - Public API

    /// Returns true when a provider + API key have been configured successfully
    var isConfigured: Bool {
        if activeModel == nil { reconfigure() }
        return activeModel != nil
    }

    func chat(_ userText: String) async -> String {
        // Re-attempt configuration if activeModel is nil (e.g. first call after login)
        if activeModel == nil { reconfigure() }
        guard let model = activeModel else {
            return "AI agent is not configured. Please set your provider and API key in Profile → Advanced → Configure AI Agent."
        }

        // Track incoming messages timestamp silently
        if let incoming = lastIncomingMessageDate, incoming != lastCheckedIncomingDate {
            lastCheckedIncomingDate = incoming
        }

        // Store raw userText in history (used for display + persistence)
        conversationHistory.append(.user(userText))
        saveHistory()

        var tools: ToolSet = [
            "send_sphinx_message": buildSendMessageTool().eraseToTool(),
            "read_recent_messages": buildReadMessagesTool().eraseToTool()
        ]
        if let key = tavilyApiKey, !key.isEmpty {
            tools["web_search"] = buildWebSearchTool(apiKey: key).eraseToTool()
        }

        let result: any GenerateTextResult
        do {
            result = try await generateText(
                model: model,
                tools: tools,
                system: systemPrompt,
                messages: conversationHistory,
                stopWhen: [stepCountIs(10)]
            )
        } catch {
            // generateText can throw even after tools succeed (e.g. second-turn API error).
            // Return the error description as a graceful message rather than propagating.
            print("AIAgentManager: generateText error – \(error)")
            let errText = "Sorry, I encountered an error: \(error.localizedDescription)"
            conversationHistory.append(.assistant(errText))
            saveHistory()
            return errText
        }

        // If the model ran a tool but produced no final text, synthesise a short reply
        var responseText = result.text.isEmpty ? "Done." : result.text

        // Safety net for send_sphinx_message: override LLM response if it contradicts
        // a successful tool result.
        outer: for step in result.steps {
            for toolResult in step.toolResults {
                guard toolResult.toolName == "send_sphinx_message" else { continue }
                guard case .string(let toolOutput) = toolResult.output else { continue }
                guard toolOutput.hasPrefix("Message sent successfully") else { continue }
                let lower = responseText.lowercased()
                let impliesFailure = lower.contains("fail") || lower.contains("unable") ||
                    lower.contains("couldn't") || lower.contains("couldn") ||
                    lower.contains("sorry") || lower.contains("did not") ||
                    lower.contains("didn't") || lower.contains("not send") ||
                    lower.contains("error")
                if impliesFailure || responseText == "Done." {
                    responseText = toolOutput
                }
                break outer
            }
        }

        // Safety net for read_recent_messages: if the tool returned messages but the LLM
        // says there was a format/reading issue, show the raw tool output instead.
        outer2: for step in result.steps {
            for toolResult in step.toolResults {
                guard toolResult.toolName == "read_recent_messages" else { continue }
                guard case .string(let toolOutput) = toolResult.output else { continue }
                guard toolOutput.hasPrefix("Messages in") || toolOutput.hasPrefix("No messages") ||
                      toolOutput.hasPrefix("Found") || toolOutput.hasPrefix("No contact") else { continue }
                print("AIAgent: read_recent_messages tool output: \(toolOutput.prefix(200))")
                print("AIAgent: LLM responseText: \(responseText.prefix(200))")
                let lower = responseText.lowercased()
                let impliesError = lower.contains("format") || lower.contains("couldn't") ||
                    lower.contains("couldn") || lower.contains("unable") ||
                    lower.contains("error") || lower.contains("sorry")
                if impliesError || responseText == "Done." {
                    responseText = toolOutput
                }
                break outer2
            }
        }

        conversationHistory.append(.assistant(responseText))
        saveHistory()
        return responseText
    }

    func reset() {
        conversationHistory = []
        lastCheckedIncomingDate = nil
        UserDefaults.standard.removeObject(forKey: historyDefaultsKey)
    }

    // MARK: - NotificationCenter

    private func observeIncomingMessages() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onNewMessages),
            name: .shouldReloadChatLists,
            object: nil
        )
    }

    @objc private func onNewMessages() {
        lastIncomingMessageDate = Date()
    }

    // MARK: - Tool: send_sphinx_message

    private struct SendMessageInput: Codable, Sendable {
        let contactName: String
        let messageText: String
    }



    private func buildSendMessageTool() -> TypedTool<SendMessageInput, JSONValue> {
        tool(
            description: "Send a Sphinx message to a contact or tribe by name. Always confirm with the user before calling this tool.",
            execute: { (input: SendMessageInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let result = await AIAgentManager.executeSendMessage(
                    contactName: input.contactName,
                    messageText: input.messageText
                )
                return .value(.string(result))
            }
        )
    }

    private static func executeSendMessage(contactName: String, messageText: String) async -> String {
        // All Core Data access and the actual send must happen on the main thread.
        return await MainActor.run {
            // 1. Try contact match
            let contacts = UserContact.getAll()
            if let contact = contacts.first(where: {
                ($0.nickname ?? "").caseInsensitiveCompare(contactName) == .orderedSame
            }) {
                guard let chat = contact.getConversation() else {
                    return "Send failed: chat not found for contact '\(contactName)'."
                }
                let (_, error) = SphinxOnionManager.sharedInstance.sendMessage(
                    to: contact,
                    content: messageText,
                    chat: chat,
                    provisionalMessage: nil,
                    threadUUID: nil,
                    replyUUID: nil
                )
                if let error = error {
                    return "Send failed: \(error)"
                }
                return "Message sent successfully to \(contact.nickname ?? contactName)."
            }

            // 2. Try tribe match
            let tribes = Chat.getAllTribes()
            if let tribe = tribes.first(where: {
                ($0.name ?? "").caseInsensitiveCompare(contactName) == .orderedSame
            }) {
                let (_, error) = SphinxOnionManager.sharedInstance.sendMessage(
                    to: nil,
                    content: messageText,
                    chat: tribe,
                    provisionalMessage: nil,
                    threadUUID: nil,
                    replyUUID: nil
                )
                if let error = error {
                    return "Send failed: \(error)"
                }
                return "Message sent successfully to tribe '\(tribe.name ?? contactName)'."
            }

            return "No contact or tribe found with name '\(contactName)'."
        }
    }

    // MARK: - Tool: web_search

    private func buildWebSearchTool(apiKey: String) -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")])
                ]),
                "required": .array([.string("query")])
            ]))
        )
        return tool(
            description: "Search the internet for current events, facts, or any topic. Returns top results with title, snippet, and URL.",
            inputSchema: inputSchema,
            execute: { (input: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard case .object(let dict) = input,
                      case .string(let query) = dict["query"] else {
                    return .value(.string("Error: missing query parameter."))
                }
                guard let url = URL(string: "https://api.tavily.com/search") else {
                    return .value(.string("Error: could not construct search URL."))
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "api_key": apiKey,
                    "query": query,
                    "max_results": 5
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (data, _) = try await URLSession.shared.data(for: request)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [[String: Any]] else {
                        return .value(.string("No results found."))
                    }
                    let lines: [String] = results.prefix(5).compactMap { result in
                        let title   = result["title"]   as? String ?? "(no title)"
                        let snippet = result["content"] as? String ?? ""
                        let link    = result["url"]     as? String ?? ""
                        return "Title: \(title) | Snippet: \(snippet) | URL: \(link)"
                    }
                    return .value(.string(lines.isEmpty ? "No results found." : lines.joined(separator: "\n")))
                } catch {
                    return .value(.string("Search failed: \(error.localizedDescription)"))
                }
            }
        )
    }

    // MARK: - Tool: read_recent_messages

    private func buildReadMessagesTool() -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "contact_name": .object(["type": .string("string")]),
                    "limit": .object(["type": .string("integer")])
                ]),
                "required": .array([.string("contact_name")])
            ]))
        )
        return tool(
            description: "Read recent messages from a conversation with a specific Sphinx contact or tribe.",
            inputSchema: inputSchema,
            execute: { (input: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard case .object(let dict) = input,
                      case .string(let contactName) = dict["contact_name"] else {
                    return .value(.string("Error: missing contact_name parameter."))
                }
                let limit: Int
                if case .number(let n) = dict["limit"] { limit = Int(n) } else { limit = 20 }

                print("AIAgent read_recent_messages: contactName=\(contactName) limit=\(limit)")

                let output: String = await MainActor.run {
                    // 1. Try contact
                    let contacts = UserContact.getAll()
                    var resolvedChat: Chat? = contacts.first(where: {
                        ($0.nickname ?? "").caseInsensitiveCompare(contactName) == .orderedSame
                    })?.getConversation()

                    // 2. Fall back to tribe
                    if resolvedChat == nil {
                        resolvedChat = Chat.getAllTribes().first(where: {
                            ($0.name ?? "").caseInsensitiveCompare(contactName) == .orderedSame
                        })
                    }

                    guard let chat = resolvedChat else {
                        return "No contact or tribe found with name '\(contactName)'."
                    }

                    let messages = TransactionMessage.getAllMessagesFor(
                        chat: chat,
                        limit: limit
                    )

                    guard !messages.isEmpty else {
                        return "No messages found in '\(contactName)'."
                    }

                    let owner = UserContact.getOwner()
                    let isoFormatter = ISO8601DateFormatter()

                    // Only include text messages; skip payments, boosts, etc. that have no content.
                    let lines: [String] = messages.compactMap { msg in
                        let content = msg.messageContent ?? ""
                        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return nil
                        }
                        let isMe = owner.map { msg.senderId == $0.id } ?? false
                        let sender = isMe ? "Me" : (msg.senderAlias ?? contactName)
                        let dateStr = msg.date.map { isoFormatter.string(from: $0) } ?? "unknown date"
                        return "[\(sender)] \(dateStr): \(content)"
                    }

                    guard !lines.isEmpty else {
                        return "Found \(messages.count) messages in '\(contactName)' but none contained readable text."
                    }

                    return "Messages in '\(contactName)' (most recent last):\n" + lines.joined(separator: "\n")
                }

                print("AIAgent read_recent_messages: returning \(output.count) chars")
                return .value(.string(output))
            }
        )
    }
}
