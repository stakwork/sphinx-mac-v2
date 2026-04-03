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

    CRITICAL TOOL RESULT RULES:
    - Tool results that start with "Message sent" mean the message was delivered successfully. \
    Always report this as a success to the user. Do NOT say there was an error.
    - Tool results that start with "Send failed" or "No contact" mean there was a genuine failure.
    - The absence of an error message is itself confirmation of success.
    - Never assume failure unless the tool result explicitly contains the word "failed" or "error".

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

        // Notify header views to update AI button visibility
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .aiAgentReconfigured, object: nil)
        }

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

        let tools: ToolSet = [
            "send_sphinx_message": buildSendMessageTool().eraseToTool(),
            "read_recent_messages": buildReadMessagesTool().eraseToTool()
        ]

        let result: GenerateTextResult
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

        // Safety net: if any tool step succeeded but the LLM's final text implies failure,
        // replace the response with the actual tool result so the user sees correct status.
        outer: for step in result.steps {
            for toolResult in step.toolResults {
                guard toolResult.toolName == "send_sphinx_message" else { continue }
                guard case .string(let toolOutput) = toolResult.output else { continue }
                guard toolOutput.hasPrefix("Message sent") else { continue }
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

    private func buildSendMessageTool() -> TypedTool<SendMessageInput, String> {
        tool(
            description: "Send a Sphinx message to a contact or tribe by name. Always confirm with the user before calling this tool.",
            execute: { (input: SendMessageInput, _: ToolCallOptions) async throws -> ToolExecutionResult<String> in
                let result = await AIAgentManager.executeSendMessage(
                    contactName: input.contactName,
                    messageText: input.messageText
                )
                return .value(result)
            }
        )
    }

    private static func executeSendMessage(contactName: String, messageText: String) async -> String {
        // 1. Try contact match
        let contacts = UserContact.getAll()
        if let contact = contacts.first(where: {
            ($0.nickname ?? "").trim().caseInsensitiveCompare(contactName.trim()) == .orderedSame
        }) {
            guard let chat = contact.getConversation() else {
                return "Chat not found for contact: \(contactName)"
            }

            let contactId = contact.id
            let chatId = chat.id

            return await MainActor.run {
                guard let contact = UserContact.getContactWith(id: contactId),
                      let chat = Chat.getChatWith(id: chatId) else {
                    return "Could not resolve contact or chat on main actor"
                }
                let (txMsg, error) = SphinxOnionManager.sharedInstance.sendMessage(
                    to: contact,
                    content: messageText,
                    chat: chat,
                    provisionalMessage: nil,
                    threadUUID: nil,
                    replyUUID: nil
                )
                // Only treat as failure if no TransactionMessage was returned
                if txMsg == nil, let error = error {
                    return "Send failed: \(error)"
                }
                return "Message sent to \(contact.nickname ?? contactName)"
            }
        }

        // 2. Try tribe match
        let tribes = Chat.getAllTribes()
        if let tribe = tribes.first(where: {
            ($0.name ?? "").trim().caseInsensitiveCompare(contactName.trim()) == .orderedSame
        }) {
            let chatId = tribe.id
            return await MainActor.run {
                guard let chat = Chat.getChatWith(id: chatId) else {
                    return "Could not resolve tribe chat on main actor"
                }
                // Tribe messages: pass nil for recipContact
                let (txMsg, error) = SphinxOnionManager.sharedInstance.sendMessage(
                    to: nil,
                    content: messageText,
                    chat: chat,
                    provisionalMessage: nil,
                    threadUUID: nil,
                    replyUUID: nil
                )
                if txMsg == nil, let error = error {
                    return "Send failed: \(error)"
                }
                return "Message sent to tribe \(tribe.name ?? contactName)"
            }
        }

        return "No contact or tribe found with name: \(contactName)"
    }

    // MARK: - Tool: read_recent_messages

    private struct ReadMessagesInput: Codable, Sendable {
        let contactName: String
        let limit: Int?
    }

    private func buildReadMessagesTool() -> TypedTool<ReadMessagesInput, String> {
        tool(
            description: "Read recent messages from a conversation with a specific Sphinx contact or tribe.",
            execute: { (input: ReadMessagesInput, _: ToolCallOptions) async throws -> ToolExecutionResult<String> in
                // 1. Try contact
                let contacts = UserContact.getAll()
                var resolvedChat: Chat? = contacts.first(where: {
                    ($0.nickname ?? "").trim().caseInsensitiveCompare(input.contactName.trim()) == .orderedSame
                })?.getConversation()

                // 2. Fall back to tribe
                if resolvedChat == nil {
                    resolvedChat = Chat.getAllTribes().first(where: {
                        ($0.name ?? "").trim().caseInsensitiveCompare(input.contactName.trim()) == .orderedSame
                    })
                }

                guard let chat = resolvedChat else {
                    return .value("No contact or tribe found with name: \(input.contactName)")
                }

                let messages = TransactionMessage.getAllMessagesFor(
                    chat: chat,
                    limit: input.limit ?? 20
                )

                if messages.isEmpty {
                    return .value("No messages found in this chat")
                }

                let owner = UserContact.getOwner()
                let isoFormatter = ISO8601DateFormatter()

                let lines = messages.map { msg -> String in
                    let isMe = owner != nil && msg.senderId == owner!.id
                    let sender = isMe ? "Me" : (msg.senderAlias ?? input.contactName)
                    let dateStr = msg.date.map { isoFormatter.string(from: $0) } ?? "unknown date"
                    let content = msg.messageContent ?? ""
                    return "[\(sender)] \(dateStr): \(content)"
                }

                return .value(lines.joined(separator: "\n"))
            }
        )
    }
}
