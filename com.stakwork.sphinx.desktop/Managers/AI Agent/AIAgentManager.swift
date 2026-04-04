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

    - read_unseen_messages: Read only unread messages from a contact or tribe by name. Use this to check what new messages haven't been seen yet.

    - get_contacts_and_tribes: List all contacts and tribes with their names and public keys. Use this to discover who the user knows.

    - get_owner_profile: Retrieve the owner's own profile: nickname, public key, route hint, avatar URL, and default tip amount.

    - modify_owner_nickname: Change the owner's display name. IMPORTANT: Before invoking this tool, describe the change and ask for explicit confirmation. Only invoke after the user confirms.

    - set_tip_amount: Set the default tip/boost amount in sats. IMPORTANT: Before invoking this tool, describe the change and ask for explicit confirmation. Only invoke after the user confirms.

    - mark_chat_as_seen: Mark all messages in a chat as read (seen = true). Use this to clear unread counts for a contact or tribe.

    - connect_with_user: Initiate a new contact connection given a nickname, public key, and route hint. IMPORTANT: Before invoking this tool, describe who you are connecting to and ask for explicit confirmation. Only invoke after the user confirms.

    - create_tribe: Create a new Sphinx tribe with a name and description. IMPORTANT: Before invoking this tool, describe the tribe details and ask for explicit confirmation. Only invoke after the user confirms.

    CRITICAL TOOL RESULT RULES:
    - Tool results that start with "Message sent successfully" mean the message was delivered. \
    Always report this as a success. Do NOT say there was an error or that you're unsure.
    - Tool results that start with "Send failed" or "No contact" or "No tribe" mean genuine failure.
    - When read_recent_messages returns a list of messages, present them clearly to the user. \
    Do NOT say there was a format issue or that you couldn't read them.
    - Never assume failure unless the tool result explicitly contains the word "failed" or "error".
    - When web_search returns results, present them clearly with titles, snippets, and URLs. Never say you cannot search the web.
    - Tool results starting with "Unseen messages in" mean unread messages were found — present them clearly.
    - Tool results starting with "No unseen messages" mean the chat is fully read.
    - Tool results starting with "Contacts:" or "Tribes:" contain the contacts/tribes list — present it clearly.
    - Tool results starting with "Owner profile:" contain the owner's details — present them clearly.
    - Tool results starting with "Owner nickname updated" mean the rename succeeded — report success.
    - Tool results starting with "Default tip amount set" mean the tip was updated — report success.
    - Tool results starting with "Chat with" and ending with "marked as seen" mean the operation succeeded.
    - Tool results starting with "Connection request sent" mean the friend request is queued — report success.
    - Tool results starting with "Tribe '" and containing "created successfully" mean the tribe was created.

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
            "send_sphinx_message":     buildSendMessageTool().eraseToTool(),
            "read_recent_messages":    buildReadMessagesTool().eraseToTool(),
            "read_unseen_messages":    buildReadUnseenMessagesTool().eraseToTool(),
            "get_contacts_and_tribes": buildGetContactsAndTribesTool().eraseToTool(),
            "get_owner_profile":       buildGetOwnerProfileTool().eraseToTool(),
            "modify_owner_nickname":   buildModifyOwnerNicknameTool().eraseToTool(),
            "set_tip_amount":          buildSetTipAmountTool().eraseToTool(),
            "mark_chat_as_seen":       buildMarkChatAsSeenTool().eraseToTool(),
            "connect_with_user":       buildConnectWithUserTool().eraseToTool(),
            "create_tribe":            buildCreateTribeTool().eraseToTool()
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

    private struct ReadUnseenInput: Codable, Sendable {
        let contactName: String
    }
    private struct MarkSeenInput: Codable, Sendable {
        let contactName: String
    }
    private struct ModifyOwnerNicknameInput: Codable, Sendable {
        let newNickname: String
    }
    private struct SetTipAmountInput: Codable, Sendable {
        let amount: Int
    }
    private struct ConnectUserInput: Codable, Sendable {
        let nickname: String
        let publicKey: String
        let routeHint: String  // expected format: "lspPubkey_scid"
    }
    private struct CreateTribeInput: Codable, Sendable {
        let name: String
        let description: String
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

    // MARK: - Tool: read_unseen_messages

    private func buildReadUnseenMessagesTool() -> TypedTool<ReadUnseenInput, JSONValue> {
        tool(
            description: "Read only unread (unseen) messages from a conversation with a specific Sphinx contact or tribe.",
            execute: { (input: ReadUnseenInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    let contacts = UserContact.getAll()
                    var resolvedChat: Chat? = contacts.first(where: {
                        ($0.nickname ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                    })?.getConversation()
                    if resolvedChat == nil {
                        resolvedChat = Chat.getAllTribes().first(where: {
                            ($0.name ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                        })
                    }
                    guard let chat = resolvedChat else {
                        return "No contact or tribe found with name '\(input.contactName)'."
                    }
                    let context = CoreDataManager.sharedManager.getBackgroundContext()
                    let messages = chat.getReceivedUnseenMessages(context: context)
                    guard !messages.isEmpty else {
                        return "No unseen messages in '\(input.contactName)'."
                    }
                    let owner = UserContact.getOwner()
                    let isoFormatter = ISO8601DateFormatter()
                    let lines: [String] = messages.compactMap { msg in
                        let content = msg.messageContent ?? ""
                        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        let isMe = owner.map { msg.senderId == $0.id } ?? false
                        let sender = isMe ? "Me" : (msg.senderAlias ?? input.contactName)
                        let dateStr = msg.date.map { isoFormatter.string(from: $0) } ?? "unknown date"
                        return "[\(sender)] \(dateStr): \(content)"
                    }
                    guard !lines.isEmpty else {
                        return "Found \(messages.count) unseen messages in '\(input.contactName)' but none contained readable text."
                    }
                    return "Unseen messages in '\(input.contactName)' (oldest first):\n" + lines.joined(separator: "\n")
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: get_contacts_and_tribes

    private func buildGetContactsAndTribesTool() -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ]))
        )
        return tool(
            description: "List all of the user's Sphinx contacts and tribes with their names and public keys.",
            inputSchema: inputSchema,
            execute: { (_: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    let contacts = UserContact.getAll().filter { !$0.isOwner && !$0.isAgent }
                    let tribes = Chat.getAllTribes()
                    if contacts.isEmpty && tribes.isEmpty {
                        return "No contacts or tribes found."
                    }
                    var lines: [String] = []
                    if !contacts.isEmpty {
                        lines.append("Contacts:")
                        for c in contacts {
                            let name = c.nickname ?? "(unnamed)"
                            let pubkey = c.publicKey ?? "(no pubkey)"
                            let routeHint = c.routeHint ?? ""
                            let hint = routeHint.isEmpty ? "" : ", routeHint: \(routeHint)"
                            lines.append("- \(name) (pubkey: \(pubkey)\(hint))")
                        }
                    }
                    if !tribes.isEmpty {
                        lines.append("Tribes:")
                        for t in tribes {
                            lines.append("- \(t.name ?? "(unnamed)")")
                        }
                    }
                    return lines.joined(separator: "\n")
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: get_owner_profile

    private func buildGetOwnerProfileTool() -> TypedTool<JSONValue, JSONValue> {
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ]))
        )
        return tool(
            description: "Retrieve the owner's own Sphinx profile details: nickname, public key, route hint, avatar URL, and default tip amount.",
            inputSchema: inputSchema,
            execute: { (_: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    guard let owner = UserContact.getOwner() else {
                        return "Owner not found."
                    }
                    let nickname  = owner.nickname  ?? "(none)"
                    let pubkey    = owner.publicKey ?? "(none)"
                    let routeHint = owner.routeHint ?? "(none)"
                    let avatarUrl = owner.avatarUrl ?? "(none)"
                    let tipAmount = UserContact.kTipAmount
                    return """
                    Owner profile:
                    Nickname: \(nickname)
                    Public Key: \(pubkey)
                    Route Hint: \(routeHint)
                    Avatar URL: \(avatarUrl)
                    Tip Amount: \(tipAmount) sats
                    """
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: modify_owner_nickname

    private func buildModifyOwnerNicknameTool() -> TypedTool<ModifyOwnerNicknameInput, JSONValue> {
        tool(
            description: "Change the owner's display name (nickname). IMPORTANT: Before invoking this tool, describe exactly what you are about to change and ask the user for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: ModifyOwnerNicknameInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    guard let owner = UserContact.getOwner() else {
                        return "Failed: owner not found."
                    }
                    owner.nickname = input.newNickname
                    owner.managedObjectContext?.saveContext()
                    return "Owner nickname updated to '\(input.newNickname)'."
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: set_tip_amount

    private func buildSetTipAmountTool() -> TypedTool<SetTipAmountInput, JSONValue> {
        tool(
            description: "Set the default tip/boost amount in sats. IMPORTANT: Before invoking this tool, describe the change and ask the user for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: SetTipAmountInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    UserContact.kTipAmount = input.amount
                    DataSyncManager.sharedInstance.saveTipAmount(value: "\(input.amount)")
                    return "Default tip amount set to \(input.amount) sats."
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: mark_chat_as_seen

    private func buildMarkChatAsSeenTool() -> TypedTool<MarkSeenInput, JSONValue> {
        tool(
            description: "Mark all messages in a chat with a contact or tribe as read (seen = true). Useful for clearing unread counts.",
            execute: { (input: MarkSeenInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    let contacts = UserContact.getAll()
                    var resolvedChat: Chat? = contacts.first(where: {
                        ($0.nickname ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                    })?.getConversation()
                    if resolvedChat == nil {
                        resolvedChat = Chat.getAllTribes().first(where: {
                            ($0.name ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                        })
                    }
                    guard let chat = resolvedChat else {
                        return "No contact or tribe found with name '\(input.contactName)'."
                    }
                    chat.setChatMessagesAsSeen(forceSeen: true)
                    return "Chat with '\(input.contactName)' marked as seen."
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: connect_with_user

    private func buildConnectWithUserTool() -> TypedTool<ConnectUserInput, JSONValue> {
        tool(
            description: "Initiate a new Sphinx contact connection given a nickname, public key, and route hint. IMPORTANT: Before invoking this tool, describe exactly who you are connecting to and ask the user for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: ConnectUserInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    let contactInfo = "\(input.publicKey)_\(input.routeHint)"
                    SphinxOnionManager.sharedInstance.makeFriendRequest(
                        contactInfo: contactInfo,
                        nickname: input.nickname
                    )
                    return "Connection request sent to '\(input.nickname)'. They will appear in your contacts once the key exchange completes."
                }
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: create_tribe

    private func buildCreateTribeTool() -> TypedTool<CreateTribeInput, JSONValue> {
        tool(
            description: "Create a new Sphinx tribe with a name and description. IMPORTANT: Before invoking this tool, describe the tribe details and ask the user for explicit confirmation. Only invoke after the user confirms.",
            execute: { (input: CreateTribeInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let result: String = await withCheckedContinuation { continuation in
                    let params: [String: Any] = [
                        "name": input.name,
                        "description": input.description,
                        "is_tribe": true
                    ]
                    let started = SphinxOnionManager.sharedInstance.createTribe(
                        params: params,
                        callback: { _ in
                            continuation.resume(returning: "Tribe '\(input.name)' created successfully.")
                        },
                        errorCallback: { error in
                            let msg = error?.localizedDescription ?? "unknown error"
                            continuation.resume(returning: "Failed to create tribe: \(msg)")
                        }
                    )
                    if !started {
                        continuation.resume(returning: "Failed to create tribe: could not start tribe creation. Check that your seed and tribe server are available.")
                    }
                }
                return .value(.string(result))
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
