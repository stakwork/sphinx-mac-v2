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

final class AIAgentManager: @unchecked Sendable {

    static let sharedInstance = AIAgentManager()

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

    - send_sphinx_message: Send a message to one of the user's Sphinx contacts by name. \
    IMPORTANT: Before invoking this tool, you MUST describe exactly what you are about to do \
    (contact name and message text) and ask the user for explicit confirmation (e.g. "Shall I send this?"). \
    Only invoke the tool after the user confirms.

    - read_recent_messages: Read recent messages from a conversation with a specific contact. \
    Use this to look up what was said in a chat.

    Always be concise and helpful. When you're unsure about a contact's name, ask for clarification.
    """

    // MARK: - Init

    private init() {
        observeIncomingMessages()
        reconfigure()
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
            activeModel = p.chat(modelId: "claude-haiku-4-5-20251001")
        case .openAI:
            let p = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: apiKey))
            activeModel = p.chat(modelId: "gpt-5.4")
        }

        // Reset history when credentials change
        reset()

        // Notify header views to update AI button visibility
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .aiAgentReconfigured, object: nil)
        }
    }

    // MARK: - Public API

    /// Returns true when a provider + API key have been configured successfully
    var isConfigured: Bool {
        if activeModel == nil { reconfigure() }
        return activeModel != nil
    }

    func chat(_ userText: String) async throws -> String {
        // Re-attempt configuration if activeModel is nil (e.g. first call after login)
        if activeModel == nil { reconfigure() }
        guard let model = activeModel else {
            return "AI agent is not configured. Please set your provider and API key in Profile → Advanced → Configure AI Agent."
        }

        var effectiveUserText = userText
        if let incoming = lastIncomingMessageDate, incoming != lastCheckedIncomingDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            effectiveUserText = "(Note: new messages arrived at \(formatter.string(from: incoming))) \(userText)"
            lastCheckedIncomingDate = incoming
        }

        conversationHistory.append(.user(effectiveUserText))

        let tools: ToolSet = [
            "send_sphinx_message": buildSendMessageTool().eraseToTool(),
            "read_recent_messages": buildReadMessagesTool().eraseToTool()
        ]

        let result = try await generateText(
            model: model,
            tools: tools,
            system: systemPrompt,
            messages: conversationHistory,
            stopWhen: [stepCountIs(5)]
        )

        let responseText = result.text
        conversationHistory.append(.assistant(responseText))
        return responseText
    }

    func reset() {
        conversationHistory = []
        lastCheckedIncomingDate = nil
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
            description: "Send a Sphinx message to a contact by name. Always confirm with the user before calling this tool.",
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
        let contacts = UserContact.getAll()
        guard let contact = contacts.first(where: {
            ($0.nickname ?? "").caseInsensitiveCompare(contactName) == .orderedSame
        }) else {
            return "Contact not found: \(contactName)"
        }

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
            return "Message sent to \(contact.nickname ?? contactName)"
        }
    }

    // MARK: - Tool: read_recent_messages

    private struct ReadMessagesInput: Codable, Sendable {
        let contactName: String
        let limit: Int?
    }

    private func buildReadMessagesTool() -> TypedTool<ReadMessagesInput, String> {
        tool(
            description: "Read recent messages from a conversation with a specific Sphinx contact.",
            execute: { (input: ReadMessagesInput, _: ToolCallOptions) async throws -> ToolExecutionResult<String> in
                let contacts = UserContact.getAll()
                guard let contact = contacts.first(where: {
                    ($0.nickname ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                }) else {
                    return .value("Contact not found: \(input.contactName)")
                }

                guard let chat = contact.getConversation() else {
                    return .value("Chat not found for contact: \(input.contactName)")
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
                    let sender = isMe ? "Me" : (msg.senderAlias ?? contact.nickname ?? "Unknown")
                    let dateStr = msg.date.map { isoFormatter.string(from: $0) } ?? "unknown date"
                    let content = msg.messageContent ?? ""
                    return "[\(sender)] \(dateStr): \(content)"
                }

                return .value(lines.joined(separator: "\n"))
            }
        )
    }
}
