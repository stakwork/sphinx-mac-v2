//
//  GraphChatSSEManager.swift
//  Sphinx
//
//  Created on 2026-06-16.
//  Copyright © 2026 Sphinx. All rights reserved.
//

import Foundation
import LDSwiftEventSource
import SwiftyJSON

// MARK: - Delegate Protocol

protocol GraphChatSSEDelegate: AnyObject {
    func onTextDelta(_ delta: String)
    func onFinish()
    func onError(_ text: String)
    func onToolInputAvailable(_ toolName: String, _ input: String)
    func onToolCall(_ toolName: String, _ input: String)
    func onToolOutputAvailable(_ toolName: String, _ output: String)
}

// MARK: - GraphChatSSEManager

class GraphChatSSEManager: NSObject, EventHandler, @unchecked Sendable {

    static let kGraphChatEndpoint = "https://hive.sphinx.chat/api/ask/quick"

    weak var delegate: GraphChatSSEDelegate?
    private var eventSource: EventSource?
    private var isStreaming = false

    // MARK: - Org Stream state (URLSession-based)
    private var orgDataTask: URLSessionDataTask?
    private var orgSSEBuffer = ""
    private var orgConversationIdFired = false
    private var onConversationId: ((String) -> Void)?

    // MARK: - Start Stream

    func startStream(
        messages: [[String: String]],
        workspaceSlug: String,
        token: String
    ) {
        stopStream()
        isStreaming = true

        guard let url = URL(string: Self.kGraphChatEndpoint) else {
            delegate?.onError("Invalid endpoint URL.")
            return
        }

        // Build JSON body
        let body: [String: Any] = [
            "messages": messages,
            "workspaceSlug": workspaceSlug
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            delegate?.onError("Failed to serialize request body.")
            return
        }

        var config = EventSource.Config(handler: self, url: url)
        config.method = "POST"
        config.body = bodyData
        config.headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)"
        ]
        eventSource = EventSource(config: config)
        eventSource?.start()
    }

    // MARK: - Stop Stream

    func stopStream() {
        eventSource?.stop()
        eventSource = nil
        isStreaming = false
    }

    // MARK: - Org Stream (URLSession-based, to access X-Conversation-Id header)

    func startOrgStream(
        question: String,
        orgSlugs: [String],
        orgId: String,
        conversationId: String?,
        token: String,
        onConversationId: @escaping (String) -> Void
    ) {
        stopOrgStream()
        orgSSEBuffer = ""
        orgConversationIdFired = false
        self.onConversationId = onConversationId

        guard let url = URL(string: Self.kGraphChatEndpoint) else {
            delegate?.onError("Invalid endpoint URL.")
            return
        }

        var body: [String: Any] = [
            "workspaceSlugs": orgSlugs,
            "orgId": orgId,
            "skipEnrichments": true,
            "turnId": UUID().uuidString
        ]
        if let cid = conversationId {
            // Server-history mode — subsequent turns
            body["message"] = question
            body["conversationId"] = cid
        } else {
            // First turn — send full messages array so server does not require conversationId
            body["messages"] = [["role": "user", "content": question]]
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            delegate?.onError("Failed to serialize request body.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        orgDataTask = session.dataTask(with: request)
        orgDataTask?.resume()
    }

    func stopOrgStream() {
        orgDataTask?.cancel()
        orgDataTask = nil
        onConversationId = nil
    }
}

// MARK: - EventHandler

extension GraphChatSSEManager {

    func onOpened() {
        print("[GraphChatSSE] Stream opened.")
    }

    func onClosed() {
        print("[GraphChatSSE] Stream closed.")
        if isStreaming {
            isStreaming = false
            delegate?.onFinish()
        }
    }

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        let dataStr = messageEvent.data

        if dataStr == "[DONE]" {
            isStreaming = false
            delegate?.onFinish()
            return
        }

        guard let data = dataStr.data(using: .utf8) else { return }
        let json = JSON(data)

        // Handle error from server
        if let errorMsg = json["error"].string {
            isStreaming = false
            delegate?.onError(errorMsg)
            return
        }

        // Handle text delta
        if let delta = json["delta"].string, !delta.isEmpty {
            delegate?.onTextDelta(delta)
            return
        }

        // Handle type-based events
        let type = json["type"].stringValue

        switch type {
        case "text_delta":
            if let text = json["text"].string, !text.isEmpty {
                delegate?.onTextDelta(text)
            }
        case "tool_input_available":
            let toolName = json["tool_name"].stringValue
            let input = json["input"].rawString() ?? ""
            delegate?.onToolInputAvailable(toolName, input)
        case "tool_call":
            let toolName = json["tool_name"].stringValue
            let input = json["input"].rawString() ?? ""
            delegate?.onToolCall(toolName, input)
        case "tool_output_available":
            let toolName = json["tool_name"].stringValue
            let output = json["output"].rawString() ?? ""
            delegate?.onToolOutputAvailable(toolName, output)
        case "done", "finish":
            isStreaming = false
            delegate?.onFinish()
        case "error":
            let errMsg = json["message"].string ?? json["error"].string ?? "Unknown SSE error"
            isStreaming = false
            delegate?.onError(errMsg)
        default:
            // Try to extract any text content
            if let text = json["text"].string, !text.isEmpty {
                delegate?.onTextDelta(text)
            } else if let content = json["content"].string, !content.isEmpty {
                delegate?.onTextDelta(content)
            }
        }
    }

    func onComment(comment: String) {
        // No-op
    }

    func onError(error: Error) {
        print("[GraphChatSSE] Error: \(error.localizedDescription)")
        isStreaming = false
        delegate?.onError(error.localizedDescription)
    }
}

// MARK: - URLSessionDataDelegate (Org Stream)

extension GraphChatSSEManager: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse,
           let cid = http.allHeaderFields["X-Conversation-Id"] as? String,
           !orgConversationIdFired {
            orgConversationIdFired = true
            // Persist synchronously before allowing data to flow so the ID is
            // stored before any subsequent turn could be triggered.
            onConversationId?(cid)
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        orgSSEBuffer += chunk
        let events = orgSSEBuffer.components(separatedBy: "\n\n")
        orgSSEBuffer = events.last ?? ""
        for event in events.dropLast() {
            parseOrgSSEEvent(event)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        DispatchQueue.main.async {
            if let error = error {
                self.delegate?.onError(error.localizedDescription)
            } else {
                self.delegate?.onFinish()
            }
        }
    }

    private func parseOrgSSEEvent(_ event: String) {
        for line in event.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let _ = payload.data(using: .utf8) else { continue }
            DispatchQueue.main.async {
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                self.handleOrgSSEJson(json)
            }
        }
    }

    private func handleOrgSSEJson(_ json: [String: Any]) {
        let type = json["type"] as? String ?? ""
        switch type {
        case "text-delta":
            let delta = (json["delta"] as? String) ?? (json["text"] as? String) ?? ""
            if !delta.isEmpty { delegate?.onTextDelta(delta) }
        case "finish", "done":
            delegate?.onFinish()
        case "error":
            let msg = (json["errorText"] as? String) ?? (json["message"] as? String) ?? "An error occurred"
            delegate?.onError(msg)
        case "tool-input-available":
            let toolName = json["toolName"] as? String ?? ""
            let input = (json["input"] as? String) ?? ""
            delegate?.onToolInputAvailable(toolName, input)
        case "tool-call":
            let toolName = json["toolName"] as? String ?? ""
            let input = (json["args"] as? String) ?? (json["input"] as? String) ?? ""
            delegate?.onToolCall(toolName, input)
        case "tool-output-available", "tool-result":
            let toolName = json["toolName"] as? String ?? ""
            let output = (json["output"] as? String) ?? ""
            delegate?.onToolOutputAvailable(toolName, output)
        default:
            if let text = json["delta"] as? String ?? json["text"] as? String, !text.isEmpty {
                delegate?.onTextDelta(text)
            }
        }
    }
}
