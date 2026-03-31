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

class AIAgentManager {

    static let sharedInstance = AIAgentManager()

    // MARK: - State

    var conversationHistory: [ModelMessage] = []
    var lastIncomingMessageDate: Date? = nil
    private var lastCheckedIncomingDate: Date? = nil

    // MARK: - Provider

    private let provider: AnthropicProvider

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
        self.provider = createAnthropicProvider(
            settings: AnthropicProviderSettings(apiKey: Config.anthropicApiKey)
        )
        observeIncomingMessages()
    }

    // MARK: - Public API

    /// Send a message to the agent and receive a response.
    func chat(_ userText: String) async throws -> String {
        guard !Config.anthropicApiKey.isEmpty else {
            return "AI agent is not configured. Please add your Anthropic API key to Config.swift."
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
            model: .v3(provider.chat(modelId: "claude-3-5-sonnet-20241022")),
            tools: tools,
            system: systemPrompt,
            messages: conversationHistory,
            stopWhen: [stepCountIs(5)]
        )

        let responseText = result.text
        conversationHistory.append(.assistant(responseText))
        return responseText
    }

    /// Clear conversation history to start a fresh session.
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
            execute: { [weak self] (input: SendMessageInput, _) async throws -> String in
                guard let _ = self else { return "Manager deallocated." }
                return await AIAgentManager.executeSendMessage(
                    contactName: input.contactName,
                    messageText: input.messageText
                )
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

        return await MainActor.run {
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
            execute: { (input: ReadMessagesInput, _) async throws -> String in
                let contacts = UserContact.getAll()
                guard let contact = contacts.first(where: {
                    ($0.nickname ?? "").caseInsensitiveCompare(input.contactName) == .orderedSame
                }) else {
                    return "Contact not found: \(input.contactName)"
                }

                guard let chat = contact.getConversation() else {
                    return "Chat not found for contact: \(input.contactName)"
                }

                let messages = TransactionMessage.getAllMessagesFor(
                    chat: chat,
                    limit: input.limit ?? 20
                )

                if messages.isEmpty {
                    return "No messages found in this chat"
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

                return lines.joined(separator: "\n")
            }
        )
    }
}
