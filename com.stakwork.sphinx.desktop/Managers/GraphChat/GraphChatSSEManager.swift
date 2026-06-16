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

class GraphChatSSEManager: NSObject {

    static let kGraphChatEndpoint = "https://hive.sphinx.chat/api/ask/quick"

    weak var delegate: GraphChatSSEDelegate?
    private var eventSource: EventSource?
    private var isStreaming = false

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
}

// MARK: - EventHandler

extension GraphChatSSEManager: EventHandler {

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
