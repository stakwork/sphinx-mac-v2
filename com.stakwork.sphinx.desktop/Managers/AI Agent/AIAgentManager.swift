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

    private(set) var isProcessing: Bool = false

    var conversationHistory: [ModelMessage] = []
    var lastIncomingMessageDate: Date? = nil
    private var lastCheckedIncomingDate: Date? = nil

    // Canvas transcript for proposal approval flow
    var canvasChatHistory: [CanvasChatMessage] = []
    var pendingProposal: PendingProposal? = nil

    /// The currently active language model (nil if not configured)
    private var activeModel: (any LanguageModelV3)?

    /// Tracks the active provider so chat() can register the correct tools
    private var activeProvider: AIProvider = .anthropic

    /// Retained OpenAI provider instance (needed to access .tools.webSearch())
    private var openAIProvider: OpenAIProvider?

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a helpful AI assistant embedded inside the Sphinx messaging app on macOS.
    You can interact with the user's Sphinx contacts and chats using the following tools:

    - send_sphinx_message: Send a message to one of the user's Sphinx contacts or tribes by name. \
    IMPORTANT: It's not needed to confirm with the user before sending the message unless it's unclear the message content \
    or the destination of the message. Optional threadUuid (a thread root's uuid) posts the message into that tribe \
    thread. Optional replyToUuid (any message's uuid) sends it as a reply, quoting that message. Only use uuids you \
    actually read from read_recent_messages, read_unseen_messages, or read_threads — never invent one.

    - read_recent_messages: Read recent messages from a conversation with a specific contact or tribe. \
    Use this to look up what was said in a chat. Each line includes the message's uuid and, when present, \
    its thread/reply links, plus THREAD ROOT and IN THREAD markers in tribes — see the tool description \
    for the exact format.

    - web_search: Search the internet for current events, facts, or any topic requiring \
    up-to-date information. Use this whenever the user asks about recent news, prices, \
    people, or anything you may not know. Present results clearly with titles and URLs.

    - read_unseen_messages: Read only unread messages from a contact or tribe by name. Use this to check what new messages haven't been seen yet. \
    Same line format as read_recent_messages (uuid, thread/reply links, markers).

    - read_threads: List threads in a tribe, most recently active first, with each thread's root uuid, starter, \
    reply count, and last activity. Use this to find "the thread about Y" or "the last thread" — it finds threads \
    even when the root message is older than read_recent_messages' window.

    - get_contacts_and_tribes: List all contacts and tribes with their names and public keys. Use this to discover who the user knows.

    - get_owner_profile: Retrieve the owner's own profile: nickname, public key, route hint, avatar URL, and default tip amount.

    - modify_owner_nickname: Change the owner's display name. IMPORTANT: Before invoking this tool, describe the change and ask for explicit confirmation. Only invoke after the user confirms.

    - set_tip_amount: Set the default tip/boost amount in sats. IMPORTANT: Before invoking this tool, describe the change and ask for explicit confirmation. Only invoke after the user confirms.

    - mark_chat_as_seen: Mark all messages in a chat as read (seen = true). Use this to clear unread counts for a contact or tribe.

    - connect_with_user: Initiate a new contact connection given a nickname, public key, and route hint. IMPORTANT: Before invoking this tool, describe who you are connecting to and ask for explicit confirmation. Only invoke after the user confirms.

    - create_tribe: Create a new Sphinx tribe with a name and description. IMPORTANT: Before invoking this tool, describe the tribe details and ask for explicit confirmation. Only invoke after the user confirms.

    - read_app_logs: Query and optionally analyse app diagnostic logs (last 24 hours). \
      Filter by: limit, start_date/end_date (ISO8601), level (debug/info/warning/error), keyword. \
      Add analyze_for to trigger structured analysis — use this whenever the user asks \
      a diagnostic question like "any MQTT errors?" or "what caused the crash at 8AM?". \
      Current device time is always injected in the tool description to resolve relative time references.

    - query_hive_graph: Query the Hive org knowledge graph via Jamie (the Hive AI agent). \
      DEFAULT tool for any Hive question that is analytical, open-ended, or needs org-wide \
      context — project status, team activity, architecture, "what are we working on", recent \
      changes, or any cross-entity question. No workspace name needed. Prefer this over \
      specific Hive tools unless the user explicitly requests a targeted CRUD operation. \
      Jamie has no notion of "the user" or "I" — when the question is about the owner \
      themselves, phrase it using their actual name (the tool description below carries \
      the owner's current Sphinx nickname for this).

    HIVE AGENT — JAMIE (DEFAULT FOR OPEN-ENDED HIVE QUESTIONS):
    Jamie is the Hive org AI agent accessible via query_hive_graph. You do NOT need the user \
    to mention "Jamie" — call query_hive_graph proactively whenever the user's question is \
    analytical, open-ended, or requires org-wide understanding. Trigger it immediately when \
    the user:
    - Asks any broad or summary question about workspaces, features, tasks, or the codebase \
      (e.g. "What are we working on?", "Any bugs in progress?", "Status of our project?")
    - Asks about team activity, architecture, design decisions, recent commits, or progress
    - Asks a cross-entity question spanning multiple workspaces, features, or tasks
    - Explicitly mentions Jamie in any form ("ask Jamie", "tell Jamie", "what does Jamie think?")

    Use specific Hive tools ONLY when the user explicitly requests a targeted CRUD operation:
    - "List my workspaces" → list_hive_workspaces
    - "Show details for feature X" → get_feature_detail
    - "What's the plan for feature X?" → get_feature_plan
    - "Catch me up on planning" / "What has the planner said?" → get_feature_plan_chat
    - "Tell the planner ..." (free-form instruction, no specific question being answered) → send_to_planner (with confirmation; call at most once per user request, never retry after busy/unknown)
    - "Answer the planner's questions ..." / "Pick option B for Q1" (answering open PLAN clarifying questions) → answer_planner_form (with confirmation; call at most once per user request, never retry after busy/unknown)
    - "Create feature X" → create_feature (with confirmation)
    - "Update task X to DONE" → update_task_status (with confirmation)

    When in doubt, prefer query_hive_graph. Never ask the user which tool to use. \
    Do NOT ask for a workspace name before calling query_hive_graph.

    JAMIE CONVERSATION RESET (new_conversation):
    query_hive_graph accepts an optional `new_conversation: true` flag that starts a \
    brand-new Jamie conversation for that org, discarding earlier context. Decide per call:
    - Omit the flag (continue) for follow-ups, clarifications, pronouns like "it" or \
      "that feature", or any refinement of the same subject as earlier Jamie questions \
      in this chat.
    - Set `new_conversation: true` only when the question is about a clearly different \
      feature, workspace, or question type than earlier Jamie questions in this chat.
    - When in doubt, do NOT set the flag — continue the existing conversation.
    - If the tool result contains "[Kept the existing conversation: a proposal in this \
      org is awaiting approval.]", the reset was held back by a pending proposal — \
      mention that pending proposal to the user if it's relevant to their question.

    ## Hive Workspace / Feature / Task Tools

    ### Read Tools (no confirmation required)
    - list_hive_workspaces: List all Hive workspaces the user has access to with name, slug, role, and member count.
    - get_workspace_detail: Get full details about a workspace (description, members list) by workspace name.
    - search_workspace: Search within a workspace for tasks, features, or content matching a query string.
    - list_features: List all features in a workspace. Includes feature title, status, and ID. Shows a hint if more exist.
    - get_feature_detail: Get detailed info about a specific feature (title, status, priority, description, workflow status, task count) by name.
    - get_feature_plan: Get a feature's plan (brief, user stories, requirements, architecture, workflow status) by workspace_name and feature_name.
    - get_feature_plan_chat: Get the last 30 planner chat messages (and artifact summaries) for a feature, plus any open clarifying questions (with message id, usable as planner_message_id for answer_planner_form).
    - list_tasks: List tasks in a workspace. Optionally pass include_archived=true to include archived tasks. Shows up to 50 with a hint if more exist.
    - get_task_detail: Get full details about a specific task (status, priority, assignee, feature, workflow status, repo, timestamps) by name.
    - get_task_messages: Get the last 20 chat messages for a specific task, formatted as [role]: message.

    ### Write Tools (ALL require explicit user confirmation before invocation)
    - send_to_planner: Send a free-form message to a feature's planner (no reply target). Requires workspace_name, feature_name, message. Call at most once per user request; never retry after a busy or unknown result.
    - answer_planner_form: Answer a feature's open PLAN clarifying questions. Requires workspace_name, feature_name, answer (all questions' answers combined, one block per question in order, separated by a blank line), and optional planner_message_id (defaults to the latest open clarifying-questions message). Call at most once per user request; never retry after a busy or unknown result.
    - create_feature: Create a new feature in a workspace. Requires workspace_name, title, and optional description.
    - update_feature: Update an existing feature's title or description. Requires workspace_name and feature_name.
    - trigger_task_generation: Trigger automatic AI task generation for a feature. Requires workspace_name and feature_name.
    - update_task_status: Change a task's status. Valid values: TODO, IN_PROGRESS, DONE, CANCELLED, BLOCKED.
    - start_task: Start (assign and begin) a task. Requires workspace_name and task_name.
    - retry_task_workflow: Retry the workflow for a failed or stalled task.
    - archive_task: Archive a task so it no longer appears in active task lists.

    ### Hive Ambiguity Behaviour
    - If a workspace/feature/task name is ambiguous, the tool returns a list of candidates — ask the user to clarify before retrying.
    - All workspace/feature/task lookups use fuzzy name matching (exact → contains → Levenshtein).
    - Write tools must never be called until the user has explicitly confirmed the action.

    CRITICAL TOOL RESULT RULES:
    - Tool results that start with "Message sent successfully" mean the message was delivered. \
    Always report this as a success. Do NOT say there was an error or that you're unsure.
    - Tool results that start with "Send failed" or "No contact" or "No tribe" mean genuine failure — explain the specific reason given.
    - Tool results starting with "Read threads failed:" mean the read_threads call failed — explain the specific reason given.
    - Tool results starting with "Threads in '" mean threads were found — present them clearly (root uuid, starter, reply count, last activity).
    - Tool results starting with "No threads found in '" are a successful empty result, not a failure — tell the user no threads were found.
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
    - Tool results starting with "Multiple matches found:" mean the name was ambiguous — list the options and ask the user which one they meant before retrying the tool with the exact name.
    - Results starting with "App logs" contain filtered log entries — present them clearly; summarise patterns if the list is long.
    - Results starting with "Log analysis for" contain a structured summary — present it directly; do not re-list raw lines.
    - Results starting with "No entries matching" mean filters returned nothing — tell the user and suggest broader filters.
    - Results starting with "Graph answer:" or any non-error text from query_hive_graph contain the knowledge graph response — present it clearly.
    - Results starting with "Hive graph error" or "Failed to fetch" from query_hive_graph mean the tool failed — report the issue and suggest checking Hive configuration.
    - Results starting with "Hive workspaces" contain the workspace list — present it clearly.
    - Results starting with "Workspace:" contain workspace detail — present it clearly.
    - Results starting with "Search results in" contain search hits — present them clearly.
    - Results starting with "Features in" contain the feature list — present it clearly.
    - Results starting with "Feature:" contain feature detail — present it clearly.
    - Results starting with "Tasks in" contain the task list — present it clearly.
    - Results starting with "Task:" contain task detail — present it clearly.
    - Results starting with "Messages for task" contain task chat messages — present them clearly.
    - Results starting with "Feature '" and containing "created successfully" mean the feature was created — report success.
    - Results starting with "Feature '" and containing "updated successfully" mean the feature was updated — report success.
    - Results starting with "Task generation triggered" mean the generation started — report success.
    - Results starting with "Task '" and containing "status updated" mean the status change succeeded — report success.
    - Results starting with "Task '" and containing "started" mean the task was started — report success.
    - Results starting with "Workflow retry triggered" mean the retry was initiated — report success.
    - Results starting with "Task '" and containing "archived" mean the task was archived — report success.
    - Results starting with "Multiple features match" or "Multiple tasks match" mean the name was ambiguous — list the candidates and ask the user to clarify before retrying with the exact name.
    - Results starting with "No feature found" or "No task found" mean the item was not found — tell the user and list the available options.

    THREADS & REPLIES:
    - A thread id is the root message's uuid — the same uuid shown on a "THREAD ROOT" line or as the \
    root_uuid of a read_threads entry.
    - Always read before you pick a uuid (read_recent_messages, read_unseen_messages, or read_threads). \
    Never invent a uuid.
    - "Last message from X" means the most recent line whose sender is X. In a 1:1 chat the sender is \
    the contact's own name. In a tribe it is their alias.
    - In a tribe, prefer lines without "[IN THREAD]" for "the last message" unless the user explicitly \
    refers to a thread. Replying to an "[IN THREAD]" message posts the reply into that same thread.
    - "The last thread" means the first result returned by read_threads.
    - Only take a threadUuid value from a read_threads result or a "THREAD ROOT" line — never from a \
    plain message line's own uuid.
    - If more than one thread could match what the user means (e.g. two threads both "about Y"), ask \
    the user which one they mean instead of guessing.

    Always be concise and helpful. When you're unsure about a contact's name, ask for clarification.

    PROPOSAL APPROVALS:
    When Jamie proposes a feature, initiative, or milestone, the query_hive_graph tool result will \
    contain a [PROPOSAL CARD DISPLAYED] block like this:

    [PROPOSAL CARD DISPLAYED — A native approval card has been shown to the user.]
    proposalId: prop_xyz123
    kind: feature
    title: Some Title

    When you see this block in the tool result, a card is showing in the UI. The proposalId is \
    the exact string on the "proposalId:" line — copy it verbatim.

    If the user then says "approve", "yes", "go ahead", "reject", "no", or similar:
    - Call approve_proposal with that exact proposalId string
    - Or call reject_proposal with that exact proposalId string

    NEVER ask the user to provide the proposalId. NEVER look for it in Hive Canvas or the web. \
    It is always present in the [PROPOSAL CARD DISPLAYED] block from the tool result above.
    Do NOT fabricate proposalIds — use only the one shown in [PROPOSAL CARD DISPLAYED].
    - Results starting with "Proposal approved successfully" mean the approval succeeded — report success.
    - Results starting with "Proposal rejected" mean the rejection succeeded — report success.
    - Results starting with "Approval failed" or "Rejection failed" mean the request failed — tell the user to try again.
    - Results starting with "Proposal not found" mean the proposalId is invalid — do not retry.
    - Results starting with "This proposal has already been actioned" mean it was already handled — inform the user.
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
    func reconfigure(clearHistory: Bool = false) {
        let userData = UserData.sharedInstance
        let providerRaw = userData.getAIAgentValue(with: .aiAgentProvider) ?? ""
        let apiKey      = userData.getAIAgentValue(with: .aiAgentApiKey)   ?? ""
        let provider    = AIProvider(rawValue: providerRaw) ?? .anthropic

        activeProvider = provider

        guard !apiKey.isEmpty else {
            activeModel = nil
            return
        }

        switch provider {
        case .anthropic:
            openAIProvider = nil
            let p = createAnthropicProvider(settings: AnthropicProviderSettings(apiKey: apiKey))
            activeModel = p.chat(modelId: "claude-sonnet-4-6")
        case .openAI:
            let p = createOpenAIProvider(settings: OpenAIProviderSettings(apiKey: apiKey))
            openAIProvider = p
            // Responses API is required for native web search support
            activeModel = p.responses(modelId: "gpt-4o")
        }

        // Reset history when credentials change
        if clearHistory {
            reset()
        }

        // Pre-cache Hive org info in the background. Load the full org list; only
        // when the user belongs to exactly one org do we also prefetch its slugs here.
        // Multi-org users' slugs load lazily on that org's first query_hive_graph call
        // (no N-way fan-out at startup).
        Task {
            await AIAgentManager.fetchAndCacheHiveOrgs()
            if let only = AIAgentManager.defaultOrg {
                await AIAgentManager.fetchAndCacheOrgSlugs(org: only)
            }
        }

        // Create agent contact + chat if not already present
        Task { @MainActor in
            self.createAgentContactAndChatIfNeeded()
        }
    }

    // MARK: - Agent Contact + Chat Creation

    @MainActor
    func createAgentContactAndChatIfNeeded() {
        guard let owner = UserContact.getOwner() else { return }
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

        isProcessing = true

        // Track incoming messages timestamp silently
        if let incoming = lastIncomingMessageDate, incoming != lastCheckedIncomingDate {
            lastCheckedIncomingDate = incoming
        }

        // Store raw userText in history (used for display + persistence)
        conversationHistory.append(.user(userText))
        saveHistory()

        // Resolved once per turn (Core Data is main-confined) and threaded into
        // query_hive_graph's description — see buildQueryHiveGraphTool(ownerNickname:orgs:).
        let ownerNickname: String? = await MainActor.run { UserContact.getOwner()?.nickname }
        // Read fresh each turn so the agent always has an up-to-date org list.
        let hiveOrgs = AIAgentManager.cachedHiveOrgs()

        var tools: ToolSet = [
            "send_sphinx_message":     buildSendMessageTool().eraseToTool(),
            "read_recent_messages":    buildReadMessagesTool().eraseToTool(),
            "read_threads":            buildReadThreadsTool().eraseToTool(),
            "read_unseen_messages":    buildReadUnseenMessagesTool().eraseToTool(),
            "get_contacts_and_tribes": buildGetContactsAndTribesTool().eraseToTool(),
            "get_owner_profile":       buildGetOwnerProfileTool().eraseToTool(),
            "modify_owner_nickname":   buildModifyOwnerNicknameTool().eraseToTool(),
            "set_tip_amount":          buildSetTipAmountTool().eraseToTool(),
            "mark_chat_as_seen":       buildMarkChatAsSeenTool().eraseToTool(),
            "connect_with_user":       buildConnectWithUserTool().eraseToTool(),
            "create_tribe":            buildCreateTribeTool().eraseToTool(),
            "read_app_logs":           buildReadAppLogsTool().eraseToTool(),
            "query_hive_graph":        buildQueryHiveGraphTool(ownerNickname: ownerNickname, orgs: hiveOrgs).eraseToTool(),
            // Hive workspace/feature/task tools
            "list_hive_workspaces":    buildListHiveWorkspacesTool().eraseToTool(),
            "get_workspace_detail":    buildGetWorkspaceDetailTool().eraseToTool(),
            "search_workspace":        buildSearchWorkspaceTool().eraseToTool(),
            "list_features":           buildListFeaturesTool().eraseToTool(),
            "get_feature_detail":      buildGetFeatureDetailTool().eraseToTool(),
            "list_tasks":              buildListTasksTool().eraseToTool(),
            "get_task_detail":         buildGetTaskDetailTool().eraseToTool(),
            "get_task_messages":       buildGetTaskMessagesTool().eraseToTool(),
            "get_feature_plan":        buildGetFeaturePlanTool().eraseToTool(),
            "get_feature_plan_chat":   buildGetFeaturePlanChatTool().eraseToTool(),
            "send_to_planner":         buildSendToPlannerTool().eraseToTool(),
            "answer_planner_form":     buildAnswerPlannerFormTool().eraseToTool(),
            "create_feature":          buildCreateFeatureTool().eraseToTool(),
            "update_feature":          buildUpdateFeatureTool().eraseToTool(),
            "trigger_task_generation": buildTriggerTaskGenerationTool().eraseToTool(),
            "update_task_status":      buildUpdateTaskStatusTool().eraseToTool(),
            "start_task":              buildStartTaskTool().eraseToTool(),
            "retry_task_workflow":     buildRetryTaskWorkflowTool().eraseToTool(),
            "archive_task":            buildArchiveTaskTool().eraseToTool(),
            "approve_proposal":        buildApproveProposalTool().eraseToTool(),
            "reject_proposal":         buildRejectProposalTool().eraseToTool()
        ]
        switch activeProvider {
        case .anthropic:
            tools["web_search"] = anthropicTools.webSearch20250305(.init(maxUses: 5))
        case .openAI:
            if let p = openAIProvider {
                tools["web_search"] = p.tools.webSearch()
            }
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
            isProcessing = false
            return errText
        }

        // If the model ran a tool but produced no final text, synthesise a short reply
        var responseText = result.text.isEmpty ? "Done." : result.text

        // Safety net for send_sphinx_message: override LLM response if it contradicts
        // a successful tool result.
        // outer: for step in result.steps {
        //     for toolResult in step.toolResults {
        //         guard toolResult.toolName == "send_sphinx_message" else { continue }
        //         guard case .string(let toolOutput) = toolResult.output else { continue }
        //         guard toolOutput.hasPrefix("Message sent successfully") else { continue }
        //         let lower = responseText.lowercased()
        //         let impliesFailure = lower.contains("fail") || lower.contains("unable") ||
        //             lower.contains("couldn't") || lower.contains("couldn") ||
        //             lower.contains("sorry") || lower.contains("did not") ||
        //             lower.contains("didn't") || lower.contains("not send") ||
        //             lower.contains("error")
        //         if impliesFailure || responseText == "Done." {
        //             responseText = toolOutput
        //         }
        //         break outer
        //     }
        // }

        // Safety net for read_recent_messages: if the tool returned messages but the LLM
        // says there was a format/reading issue, show the raw tool output instead.
        //
        // Restricted to turns whose LAST tool call was a read, and where no
        // send_sphinx_message ran in this turn — otherwise a genuine
        // "Send failed: …" explanation (which can legitimately contain words
        // like "error"/"unable") would get replaced by a dump of uuids.
        let allToolNames: [String] = result.steps.flatMap { step in
            step.toolResults.map { $0.toolName }
        }
        let sentInThisTurn = allToolNames.contains("send_sphinx_message")
        let lastToolWasRead = allToolNames.last == "read_recent_messages"

        if !sentInThisTurn && lastToolWasRead {
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
        }

        conversationHistory.append(.assistant(responseText))
        saveHistory()
        isProcessing = false
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

    // MARK: - Name Resolution

    private enum NameResolutionResult {
        case exactContact(UserContact)
        case exactTribe(Chat)
        case ambiguous([String])  // e.g. ["Contact: Alexander", "Tribe: Alex's Node"]
        case noMatch
    }

    /// Normalise a name: trim, replace underscores with spaces, collapse whitespace, lowercase.
    private static func normalizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let underscoresAsSpaces = trimmed.replacingOccurrences(of: "_", with: " ")
        let components = underscoresAsSpaces.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return components.joined(separator: " ").lowercased()
    }

    /// Remove all spaces — used for "tomtest2" ↔ "Tom Test 2" comparison.
    private static func stripSpaces(_ name: String) -> String {
        return name.replacingOccurrences(of: " ", with: "")
    }

    /// Levenshtein edit distance between two strings.
    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                curr[j] = aChars[i-1] == bChars[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[n]
    }

    @MainActor
    private static func resolveContactOrTribe(
        query: String,
        tribesOnly: Bool = false
    ) -> NameResolutionResult {
        let normalizedQuery = normalizeName(query)
        let strippedQuery   = stripSpaces(normalizedQuery)

        let contacts = tribesOnly ? [] : UserContact.getAll().filter { !$0.isOwner && !$0.isAgent }
        let tribes   = Chat.getAllTribes()

        // Helper closures
        let normContact: (UserContact) -> String = { normalizeName($0.nickname ?? "") }
        let normTribe:   (Chat)        -> String = { normalizeName($0.name    ?? "") }

        // Pass 1 — exact normalised match (handles underscore↔space equivalence)
        for contact in contacts where normContact(contact) == normalizedQuery {
            return .exactContact(contact)
        }
        for tribe in tribes where normTribe(tribe) == normalizedQuery {
            return .exactTribe(tribe)
        }

        // Pass 2 — space-stripped exact match (handles "tomtest2" ↔ "Tom Test 2")
        if !strippedQuery.isEmpty {
            for contact in contacts where stripSpaces(normContact(contact)) == strippedQuery {
                return .exactContact(contact)
            }
            for tribe in tribes where stripSpaces(normTribe(tribe)) == strippedQuery {
                return .exactTribe(tribe)
            }
        }

        // Pass 3 — partial / contains match
        var candidates: [(label: String, contact: UserContact?, tribe: Chat?)] = []
        for contact in contacts {
            let n = normContact(contact)
            if n.contains(normalizedQuery) || stripSpaces(n).contains(strippedQuery) {
                candidates.append((label: "Contact: \(contact.nickname ?? "")", contact: contact, tribe: nil))
            }
        }
        for tribe in tribes {
            let n = normTribe(tribe)
            if n.contains(normalizedQuery) || stripSpaces(n).contains(strippedQuery) {
                candidates.append((label: "Tribe: \(tribe.name ?? "")", contact: nil, tribe: tribe))
            }
        }

        if !candidates.isEmpty {
            return candidates.count == 1
                ? (candidates[0].contact.map { .exactContact($0) } ?? candidates[0].tribe.map { .exactTribe($0) } ?? .noMatch)
                : .ambiguous(candidates.map { $0.label })
        }

        // Pass 4 — fuzzy (Levenshtein) match; threshold scales with query length
        let threshold = max(1, normalizedQuery.count / 4)
        var fuzzyCandidates: [(label: String, contact: UserContact?, tribe: Chat?, dist: Int)] = []
        for contact in contacts {
            let d = levenshteinDistance(normContact(contact), normalizedQuery)
            if d <= threshold {
                fuzzyCandidates.append((label: "Contact: \(contact.nickname ?? "")", contact: contact, tribe: nil, dist: d))
            }
        }
        for tribe in tribes {
            let d = levenshteinDistance(normTribe(tribe), normalizedQuery)
            if d <= threshold {
                fuzzyCandidates.append((label: "Tribe: \(tribe.name ?? "")", contact: nil, tribe: tribe, dist: d))
            }
        }

        // Sort by edit distance so the closest match wins on single-result
        fuzzyCandidates.sort { $0.dist < $1.dist }

        switch fuzzyCandidates.count {
        case 0:
            return .noMatch
        case 1:
            if let contact = fuzzyCandidates[0].contact { return .exactContact(contact) }
            if let tribe   = fuzzyCandidates[0].tribe   { return .exactTribe(tribe) }
            return .noMatch
        default:
            // If the closest match is clearly better (distance gap ≥ 2), pick it
            if fuzzyCandidates[0].dist + 2 <= fuzzyCandidates[1].dist {
                if let contact = fuzzyCandidates[0].contact { return .exactContact(contact) }
                if let tribe   = fuzzyCandidates[0].tribe   { return .exactTribe(tribe) }
            }
            return .ambiguous(fuzzyCandidates.map { $0.label })
        }
    }

    @MainActor
    private static func recentMessagesOutput(chat: Chat, chatName: String, limit: Int) -> String {
        // getAllMessagesFor sorts `date DESC, id DESC` (newest first); reverse
        // so the output genuinely is "most recent last".
        let messagesNewestFirst = TransactionMessage.getAllMessagesFor(chat: chat, limit: limit)
        guard !messagesNewestFirst.isEmpty else { return "No messages found in '\(chatName)'." }
        let messages = messagesNewestFirst.reversed()

        guard let owner = UserContact.getOwner() else { return "Could not determine owner." }
        let contact = chat.getContact()
        let resolvedContactName = contact?.nickname ?? chatName
        let isTribe = chat.isPublicGroup()

        // Threads are tribe-only. Only in tribes, batch-fetch reply counts
        // over the union of this page's uuids + threadUUIDs so THREAD
        // ROOT / IN THREAD markers match what the app's own Threads list
        // would show.
        var rootUUIDs: Set<String> = []
        var replyCounts: [String: Int] = [:]
        if isTribe {
            var uuidSet = Set<String>()
            for msg in messages {
                if let uuid = msg.uuid { uuidSet.insert(uuid) }
                if let threadUUID = msg.threadUUID { uuidSet.insert(threadUUID) }
            }
            let threadReplies = TransactionMessage.getThreadMessagesFor(Array(uuidSet), on: chat)
            let rows = threadReplies.compactMap { reply -> AgentThreadRow? in
                guard let date = reply.date else { return nil }
                return AgentThreadRow(uuid: reply.uuid, threadUUID: reply.threadUUID, date: date)
            }
            rootUUIDs = AIAgentThreadingRules.threadRootUUIDs(replies: rows, isTribe: isTribe)
            for row in rows {
                guard let threadUUID = row.threadUUID else { continue }
                replyCounts[threadUUID, default: 0] += 1
            }
        }

        let lines: [String] = messages.map { msg in
            let content = msg.getMessageContentPreview(owner: owner, contact: contact, includeSender: false)
            let isMe = msg.senderId == owner.id
            let date = msg.date ?? Date()
            let isThreadRoot = isTribe && (msg.uuid.map { rootUUIDs.contains($0) } ?? false)
            let isInThread = isTribe && !isThreadRoot &&
                (msg.threadUUID.map { rootUUIDs.contains($0) } ?? false)
            return AIAgentThreadingRules.formatLine(
                isOwner: isMe,
                isTribe: isTribe,
                senderAlias: msg.senderAlias,
                resolvedContactName: resolvedContactName,
                date: date,
                uuid: msg.uuid,
                threadUUID: msg.threadUUID,
                replyUUID: msg.replyUUID,
                isThreadRoot: isThreadRoot,
                threadReplyCount: msg.uuid.flatMap { replyCounts[$0] } ?? 0,
                isInThread: isInThread,
                content: content
            )
        }
        return "Messages in '\(chatName)' (most recent last):\n" + lines.joined(separator: "\n")
    }

    /// Snapshot of a message used by `unseenMessagesOutput` so nothing
    /// managed crosses between the background context it is fetched on and
    /// the main actor the formatted output is returned to.
    private struct UnseenMessageSnapshot {
        let id: Int
        let ref: AgentMessageRef
        let isOwner: Bool
        let senderAlias: String?
        let date: Date
        let content: String
    }

    @MainActor
    private static func unseenMessagesOutput(chat: Chat, chatName: String) -> String {
        let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
        let isTribe = chat.isPublicGroup()
        let chatId = chat.id

        guard let owner = UserContact.getOwner() else {
            return "Could not determine owner."
        }
        let ownerId = owner.id
        let contact = chat.getContact()
        let resolvedContactName = contact?.nickname ?? chatName

        var snapshots: [UnseenMessageSnapshot] = []
        var rootUUIDs: Set<String> = []
        var replyCounts: [String: Int] = [:]

        backgroundContext.performAndWait {
            let messages = chat.getReceivedUnseenMessages(context: backgroundContext)
            guard !messages.isEmpty else { return }

            if isTribe {
                var uuidSet = Set<String>()
                for msg in messages {
                    if let uuid = msg.uuid { uuidSet.insert(uuid) }
                    if let threadUUID = msg.threadUUID { uuidSet.insert(threadUUID) }
                }
                let threadReplies = TransactionMessage.getThreadMessagesFor(
                    Array(uuidSet), on: chat, context: backgroundContext
                )
                let rows = threadReplies.compactMap { reply -> AgentThreadRow? in
                    guard let date = reply.date else { return nil }
                    return AgentThreadRow(uuid: reply.uuid, threadUUID: reply.threadUUID, date: date)
                }
                rootUUIDs = AIAgentThreadingRules.threadRootUUIDs(replies: rows, isTribe: isTribe)
                for row in rows {
                    guard let threadUUID = row.threadUUID else { continue }
                    replyCounts[threadUUID, default: 0] += 1
                }
            }

            snapshots = messages.map { msg in
                UnseenMessageSnapshot(
                    id: msg.id,
                    ref: AgentMessageRef(
                        uuid: msg.uuid,
                        threadUUID: msg.threadUUID,
                        replyUUID: msg.replyUUID,
                        chatId: chatId,
                        isDeleted: msg.isDeleted()
                    ),
                    isOwner: msg.senderId == ownerId,
                    senderAlias: msg.senderAlias,
                    date: msg.date ?? Date(),
                    content: msg.getMessageContentPreview(owner: owner, contact: contact, includeSender: false)
                )
            }
        }

        guard !snapshots.isEmpty else {
            return "No unseen messages in '\(chatName)'."
        }

        // getReceivedUnseenMessages uses sortDescriptors: [], so sort
        // ourselves (oldest first) before formatting to make the label true.
        snapshots.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }

        let lines: [String] = snapshots.map { snap in
            let isThreadRoot = isTribe && (snap.ref.uuid.map { rootUUIDs.contains($0) } ?? false)
            let isInThread = isTribe && !isThreadRoot &&
                (snap.ref.threadUUID.map { rootUUIDs.contains($0) } ?? false)
            return AIAgentThreadingRules.formatLine(
                isOwner: snap.isOwner,
                isTribe: isTribe,
                senderAlias: snap.senderAlias,
                resolvedContactName: resolvedContactName,
                date: snap.date,
                uuid: snap.ref.uuid,
                threadUUID: snap.ref.threadUUID,
                replyUUID: snap.ref.replyUUID,
                isThreadRoot: isThreadRoot,
                threadReplyCount: snap.ref.uuid.flatMap { replyCounts[$0] } ?? 0,
                isInThread: isInThread,
                content: snap.content
            )
        }
        return "Unseen messages in '\(chatName)' (oldest first):\n" + lines.joined(separator: "\n")
    }

    // MARK: - Input structs

     private struct SendMessageInput: Codable, Sendable {
         let contactName: String
         let messageText: String
         let threadUuid: String?
         let replyToUuid: String?

         init(
             contactName: String,
             messageText: String,
             threadUuid: String? = nil,
             replyToUuid: String? = nil
         ) {
             self.contactName = contactName
             self.messageText = messageText
             self.threadUuid = threadUuid
             self.replyToUuid = replyToUuid
         }

         init(from decoder: Decoder) throws {
             let container = try decoder.container(keyedBy: CodingKeys.self)
             contactName = try container.decode(String.self, forKey: .contactName)
             messageText = try container.decode(String.self, forKey: .messageText)
             threadUuid = try container.decodeIfPresent(String.self, forKey: .threadUuid)
             replyToUuid = try container.decodeIfPresent(String.self, forKey: .replyToUuid)
         }
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
             description: """
                 Send a Sphinx message to a contact or tribe by name. No need to confirm with the \
                 user before calling this tool unless the message content or destination is unclear. \
                 Optional threadUuid: the root message's uuid (from read_threads or a THREAD ROOT \
                 line) to post into that tribe thread. Optional replyToUuid: a message's uuid (from \
                 read_recent_messages / read_unseen_messages / read_threads) to reply to it, quoting \
                 it like a swipe-to-reply in the app. Only use uuids you've actually read — never \
                 invent one. Combine both to reply to a specific message inside a specific thread.
                 """,
             execute: { (input: SendMessageInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                 let result = await AIAgentManager.executeSendMessage(
                     contactName: input.contactName,
                     messageText: input.messageText,
                     threadUuid: input.threadUuid,
                     replyToUuid: input.replyToUuid
                 )
                 return .value(.string(result))
             }
         )
     }

     private static func executeSendMessage(
        contactName: String,
        messageText: String,
        threadUuid: String? = nil,
        replyToUuid: String? = nil
     ) async -> String {
         return await MainActor.run {
             print("AIAgent send_sphinx_message: contactName=\(contactName) threadUuid=\(threadUuid ?? "nil") replyToUuid=\(replyToUuid ?? "nil")")

             switch resolveContactOrTribe(query: contactName) {
             case .exactContact(let contact):
                 guard let chat = contact.getConversation() else {
                     return "Send failed: chat not found for contact '\(contactName)'."
                 }
                 let isTribe = chat.isPublicGroup()

                 let (replyRef, replyValidation) = resolveAndValidateReplyTarget(
                     replyToUuid: replyToUuid, chatId: chat.id
                 )
                 if let reason = replyValidation?.reason {
                     print("AIAgent send_sphinx_message: refused — \(reason)")
                     return "Send failed: \(reason)"
                 }

                 let threadValidation = validateThread(
                     threadUuid: threadUuid, chat: chat, isTribe: isTribe
                 )
                 if let reason = threadValidation?.reason {
                     print("AIAgent send_sphinx_message: refused — \(reason)")
                     return "Send failed: \(reason)"
                 }

                 if let threadUuid = threadUuid, let replyRef = replyRef {
                     let consistency = AIAgentThreadingRules.validateThreadReplyConsistency(
                         threadUUID: threadUuid, replyTo: replyRef
                     )
                     if let reason = consistency.reason {
                         print("AIAgent send_sphinx_message: refused — \(reason)")
                         return "Send failed: \(reason)"
                     }
                 }

                 let wire = AIAgentThreadingRules.wireValues(threadUUID: threadUuid, replyTo: replyRef)
                 print("AIAgent send_sphinx_message: resolved wire thread=\(wire.thread ?? "nil") reply=\(wire.reply ?? "nil")")

                 let (_, error) = SphinxOnionManager.sharedInstance.sendMessage(
                     to: contact,
                     content: messageText,
                     chat: chat,
                     provisionalMessage: nil,
                     threadUUID: wire.thread,
                     replyUUID: wire.reply
                 )
                 if let error = error { return "Send failed: \(error)" }
                 return "Message sent successfully to \(contact.nickname ?? contactName)."
    
             case .exactTribe(let tribe):
                 let isTribe = tribe.isPublicGroup()

                 let (replyRef, replyValidation) = resolveAndValidateReplyTarget(
                     replyToUuid: replyToUuid, chatId: tribe.id
                 )
                 if let reason = replyValidation?.reason {
                     print("AIAgent send_sphinx_message: refused — \(reason)")
                     return "Send failed: \(reason)"
                 }

                 let threadValidation = validateThread(
                     threadUuid: threadUuid, chat: tribe, isTribe: isTribe
                 )
                 if let reason = threadValidation?.reason {
                     print("AIAgent send_sphinx_message: refused — \(reason)")
                     return "Send failed: \(reason)"
                 }

                 if let threadUuid = threadUuid, let replyRef = replyRef {
                     let consistency = AIAgentThreadingRules.validateThreadReplyConsistency(
                         threadUUID: threadUuid, replyTo: replyRef
                     )
                     if let reason = consistency.reason {
                         print("AIAgent send_sphinx_message: refused — \(reason)")
                         return "Send failed: \(reason)"
                     }
                 }

                 let wire = AIAgentThreadingRules.wireValues(threadUUID: threadUuid, replyTo: replyRef)
                 print("AIAgent send_sphinx_message: resolved wire thread=\(wire.thread ?? "nil") reply=\(wire.reply ?? "nil")")

                 let (_, error) = SphinxOnionManager.sharedInstance.sendMessage(
                     to: nil,
                     content: messageText,
                     chat: tribe,
                     provisionalMessage: nil,
                     threadUUID: wire.thread,
                     replyUUID: wire.reply
                 )
                 if let error = error { return "Send failed: \(error)" }
                 return "Message sent successfully to tribe '\(tribe.name ?? contactName)'."
    
             case .ambiguous(let candidates):
                 return "Multiple matches found: \(candidates.joined(separator: ", ")). Please clarify which one you mean."
    
             case .noMatch:
                 return "No contact or tribe found with name '\(contactName)'."
             }
         }
     }

     /// Looks up `replyToUuid` (if given) and validates it as a reply target.
     /// Never trusts the caller-supplied uuid: the lookup is not chat-scoped,
     /// so validation re-checks chatId/isDeleted before any send proceeds.
     @MainActor
     private static func resolveAndValidateReplyTarget(
        replyToUuid: String?,
        chatId: Int
     ) -> (AgentMessageRef?, ValidationResult?) {
         guard let replyToUuid = replyToUuid else { return (nil, nil) }
         let message = TransactionMessage.getMessageWith(uuid: replyToUuid)
         let ref = message.map {
             AgentMessageRef(
                 uuid: $0.uuid,
                 threadUUID: $0.threadUUID,
                 replyUUID: $0.replyUUID,
                 chatId: $0.chat?.id,
                 isDeleted: $0.isDeleted()
             )
         }
         let validation = AIAgentThreadingRules.validateReplyTarget(ref, chatId: chatId)
         return (ref, validation.isOK ? nil : validation)
     }

     /// Looks up `threadUuid` (if given) and validates it as a thread root.
     /// Never trusts the caller-supplied uuid: re-checks chatId/isDeleted/
     /// isTribe before any send proceeds.
     @MainActor
     private static func validateThread(
        threadUuid: String?,
        chat: Chat,
        isTribe: Bool
     ) -> ValidationResult? {
         guard let threadUuid = threadUuid else { return nil }
         let message = TransactionMessage.getMessageWith(uuid: threadUuid)
         let ref = message.map {
             AgentMessageRef(
                 uuid: $0.uuid,
                 threadUUID: $0.threadUUID,
                 replyUUID: $0.replyUUID,
                 chatId: $0.chat?.id,
                 isDeleted: $0.isDeleted()
             )
         }
         let validation = AIAgentThreadingRules.validateThreadRoot(ref, chatId: chat.id, isTribe: isTribe)
         return validation.isOK ? nil : validation
     }

    // MARK: - Tool: read_unseen_messages

    private func buildReadUnseenMessagesTool() -> TypedTool<ReadUnseenInput, JSONValue> {
        tool(
            description: """
                Read only unread (unseen) messages from a conversation with a specific Sphinx contact \
                or tribe. Same line format as read_recent_messages: \
                "[sender] date (uuid=… thread=… reply=… [THREAD ROOT, n replies] [IN THREAD]): content". \
                Read before you pick a uuid — never invent one.
                """,
            execute: { (input: ReadUnseenInput, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                print("AIAgent read_unseen_messages: contactName=\(input.contactName)")
                let output: String = await MainActor.run {
                    switch AIAgentManager.resolveContactOrTribe(query: input.contactName) {
                    case .ambiguous(let candidates):
                        return "Multiple matches found: \(candidates.joined(separator: ", ")). Please clarify which one you mean."
                    case .noMatch:
                        return "No contact or tribe found with name '\(input.contactName)'."
                    case .exactContact(let contact):
                        let resolvedChat = contact.getConversation()
                        guard let chat = resolvedChat else {
                            return "No contact or tribe found with name '\(input.contactName)'."
                        }
                        return AIAgentManager.unseenMessagesOutput(chat: chat, chatName: input.contactName)
                    case .exactTribe(let tribe):
                        return AIAgentManager.unseenMessagesOutput(chat: tribe, chatName: input.contactName)
                    }
                }
                print("AIAgent read_unseen_messages: returning \(output.count) chars")
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
                    switch AIAgentManager.resolveContactOrTribe(query: input.contactName) {
                    case .ambiguous(let candidates):
                        return "Multiple matches found: \(candidates.joined(separator: ", ")). Please clarify which one you mean."
                    case .noMatch:
                        return "No contact or tribe found with name '\(input.contactName)'."
                    case .exactContact(let contact):
                        guard let chat = contact.getConversation() else {
                            return "No contact or tribe found with name '\(input.contactName)'."
                        }
                        chat.setChatMessagesAsSeen(forceSeen: true)
                        return "Chat with '\(input.contactName)' marked as seen."
                    case .exactTribe(let tribe):
                        tribe.setChatMessagesAsSeen(forceSeen: true)
                        return "Chat with '\(input.contactName)' marked as seen."
                    }
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

    // MARK: - Tool: read_app_logs

    private func buildReadAppLogsTool() -> TypedTool<JSONValue, JSONValue> {
        let now = AppLogger.isoFormatter.string(from: Date())
        let tz  = TimeZone.current.abbreviation() ?? "UTC"
        let description = """
            Query and optionally analyse app diagnostic logs (last 24 hours). \
            Current device time: \(now) (\(tz)). \
            Filter by: limit (int, default 100, max 500), start_date/end_date (ISO8601), \
            level (debug/info/warning/error), keyword (substring). \
            Add analyze_for to get a structured analysis instead of raw lines.
            """
        let inputSchema = FlexibleSchema<JSONValue>(
            jsonSchema(.object([
                "type": .string("object"),
                "properties": .object([
                    "limit":       .object(["type": .string("integer")]),
                    "start_date":  .object(["type": .string("string")]),
                    "end_date":    .object(["type": .string("string")]),
                    "level":       .object(["type": .string("string")]),
                    "keyword":     .object(["type": .string("string")]),
                    "analyze_for": .object(["type": .string("string")])
                ]),
                "required": .array([])
            ]))
        )
        return tool(
            description: description,
            inputSchema: inputSchema,
            execute: { (input: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                let output: String = await MainActor.run {
                    // Parse optional parameters
                    var requestedLimit: Int? = nil
                    var startDate: Date? = nil
                    var endDate: Date? = nil
                    var levelFilter: String? = nil
                    var keyword: String? = nil
                    var analyzeFor: String? = nil

                    if case .object(let dict) = input {
                        if case .number(let n) = dict["limit"] { requestedLimit = Int(n) }
                        if case .string(let s) = dict["start_date"] { startDate = AppLogger.isoFormatter.date(from: s) }
                        if case .string(let s) = dict["end_date"]   { endDate = AppLogger.isoFormatter.date(from: s) }
                        if case .string(let s) = dict["level"]      { levelFilter = s.lowercased() }
                        if case .string(let s) = dict["keyword"]    { keyword = s }
                        if case .string(let s) = dict["analyze_for"] { analyzeFor = s }
                    }

                    let limit = min(requestedLimit ?? 100, 500)

                    // Filter pipeline
                    var filtered = AppLogger.shared.entries

                    if let start = startDate {
                        filtered = filtered.filter { $0.timestamp >= start }
                    }
                    if let end = endDate {
                        filtered = filtered.filter { $0.timestamp <= end }
                    }
                    if let lvl = levelFilter {
                        filtered = filtered.filter { $0.level.rawValue.lowercased() == lvl }
                    }
                    if let kw = keyword {
                        let kwLower = kw.lowercased()
                        filtered = filtered.filter { $0.message.lowercased().contains(kwLower) }
                    }

                    let truncated = filtered.count > limit
                    let finalEntries = Array(filtered.suffix(limit))
                    let matchedCount = filtered.count

                    // Build date range string for header
                    let rangeStr: String = {
                        if let s = startDate, let e = endDate {
                            return " (\(AppLogger.isoFormatter.string(from: s)) – \(AppLogger.isoFormatter.string(from: e)))"
                        } else if let s = startDate {
                            return " (from \(AppLogger.isoFormatter.string(from: s)))"
                        } else if let e = endDate {
                            return " (until \(AppLogger.isoFormatter.string(from: e)))"
                        }
                        return ""
                    }()

                    // Analysis mode
                    if let analyzeFor = analyzeFor {
                        let needle = analyzeFor.lowercased()
                        let matches = finalEntries.filter { $0.message.lowercased().contains(needle) }

                        guard !matches.isEmpty else {
                            return "No entries matching '\(analyzeFor)' found in the filtered log set (\(matchedCount) entries scanned)."
                        }

                        let pct = matchedCount > 0
                            ? String(format: "%.1f", Double(matches.count) / Double(matchedCount) * 100)
                            : "0.0"
                        let firstTs = matches.first.map { AppLogger.isoFormatter.string(from: $0.timestamp) } ?? ""
                        let lastTs  = matches.last.map  { AppLogger.isoFormatter.string(from: $0.timestamp) } ?? ""
                        let excerpts = matches.prefix(30).map { "  \($0.formatted)" }.joined(separator: "\n")
                        let showingCount = min(matches.count, 30)

                        return """
                        Log analysis for "\(analyzeFor)" in \(matchedCount) entries\(rangeStr):
                          Matches: \(matches.count) (\(pct)% of entries)
                          First: \(firstTs)
                          Last:  \(lastTs)
                          Showing \(showingCount) of \(matches.count) matching lines:
                        \(excerpts)
                        """
                    }

                    // Raw mode
                    let capNote = truncated ? " — results capped at 500" : ""
                    let header = "App logs (showing \(finalEntries.count) of \(matchedCount) matched entries, oldest first)\(capNote):"
                    let lines = finalEntries.map { "  \($0.formatted)" }.joined(separator: "\n")
                    return "\(header)\n\(lines)"
                }
                return .value(.string(output))
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
            description: """
                Read recent messages from a conversation with a specific Sphinx contact or tribe. \
                Each line is formatted as \
                "[sender] date (uuid=… thread=… reply=… [THREAD ROOT, n replies] [IN THREAD]): content". \
                uuid=pending means the message isn't confirmed yet and has no uuid to reply to or \
                thread from. thread=/reply= appear only when the message has those links. \
                THREAD ROOT marks a message that is the root of a tribe thread with 2+ replies — its \
                uuid is a valid threadUuid for send_sphinx_message. IN THREAD marks a tribe message \
                that belongs to such a thread (the app hides these from the main chat view). Read \
                before you pick a uuid — never invent one.
                """,
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
                    switch AIAgentManager.resolveContactOrTribe(query: contactName) {
                    case .ambiguous(let candidates):
                        return "Multiple matches found: \(candidates.joined(separator: ", ")). Please clarify which one you mean."
                    case .noMatch:
                        return "No contact or tribe found with name '\(contactName)'."
                    case .exactContact(let contact):
                        guard let chat = contact.getConversation() else {
                            return "No contact or tribe found with name '\(contactName)'."
                        }
                        return AIAgentManager.recentMessagesOutput(chat: chat, chatName: contactName, limit: limit)
                    case .exactTribe(let tribe):
                        return AIAgentManager.recentMessagesOutput(chat: tribe, chatName: contactName, limit: limit)
                    }
                }

                print("AIAgent read_recent_messages: returning \(output.count) chars")
                return .value(.string(output))
            }
        )
    }

    // MARK: - Tool: read_threads

    private func buildReadThreadsTool() -> TypedTool<JSONValue, JSONValue> {
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
            description: """
                List threads in a tribe, most recently active first. Finds threads even when the \
                root message is older than what read_recent_messages' window would show. Each line \
                shows the thread's root uuid (usable as threadUuid for send_sphinx_message), who \
                started it, the reply count, and when it was last active. Takes contact_name (a \
                tribe name — threads only exist in tribes) and an optional limit (default 10, max 50).
                """,
            inputSchema: inputSchema,
            execute: { (input: JSONValue, _: ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> in
                guard case .object(let dict) = input,
                      case .string(let contactName) = dict["contact_name"] else {
                    return .value(.string("Error: missing contact_name parameter."))
                }
                var limit = 10
                if case .number(let n) = dict["limit"] { limit = Int(n) }
                limit = max(1, min(limit, 50))

                print("AIAgent read_threads: contactName=\(contactName) limit=\(limit)")

                let output: String = await MainActor.run {
                    switch AIAgentManager.resolveContactOrTribe(query: contactName, tribesOnly: true) {
                    case .ambiguous(let candidates):
                        return "Multiple matches found: \(candidates.joined(separator: ", ")). Please clarify which one you mean."
                    case .noMatch:
                        return "Read threads failed: no tribe named '\(contactName)' found."
                    case .exactContact:
                        // tribesOnly resolution never returns a contact, but handle defensively.
                        return "Read threads failed: no tribe named '\(contactName)' found."
                    case .exactTribe(let tribe):
                        return AIAgentManager.readThreadsOutput(tribe: tribe, chatName: contactName, limit: limit)
                    }
                }

                print("AIAgent read_threads: returning \(output.count) chars")
                return .value(.string(output))
            }
        )
    }

    @MainActor
    private static func readThreadsOutput(tribe: Chat, chatName: String, limit: Int) -> String {
        guard tribe.isPublicGroup() else {
            return "Read threads failed: '\(chatName)' is a 1:1 chat; threads are only available in tribes."
        }

        let fetchRequest = TransactionMessage.getThreadsFetchRequestOn(chat: tribe)
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = ["uuid", "threadUUID", "date"]
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        fetchRequest.fetchLimit = 5000

        let context = CoreDataManager.sharedManager.persistentContainer.viewContext
        var rawRows: [[String: Any]] = []
        context.performAndWait {
            do {
                if let results = try context.fetch(fetchRequest) as? [[String: Any]] {
                    rawRows = results
                }
            } catch let error as NSError {
                print("AIAgent read_threads: fetch error \(error.localizedDescription)")
            }
        }
        let hitCap = rawRows.count >= 5000

        let rows: [AgentThreadRow] = rawRows.compactMap { dict in
            guard let date = dict["date"] as? Date else { return nil }
            return AgentThreadRow(
                uuid: dict["uuid"] as? String,
                threadUUID: dict["threadUUID"] as? String,
                date: date
            )
        }

        let grouped = AIAgentThreadingRules.groupThreads(rows: rows)
        guard !grouped.isEmpty else {
            print("AIAgent read_threads: chat=\(chatName) limit=\(limit) found=0 skipped=0 capHit=\(hitCap)")
            return "No threads found in '\(chatName)'."
        }

        let limited = Array(grouped.prefix(limit))
        let rootUUIDs = limited.map { $0.rootUUID }
        let roots = TransactionMessage.getOriginalMessagesFor(rootUUIDs, on: tribe)
        let rootsByUUID = Dictionary(uniqueKeysWithValues: roots.compactMap { root -> (String, TransactionMessage)? in
            guard let uuid = root.uuid else { return nil }
            return (uuid, root)
        })

        guard let owner = UserContact.getOwner() else { return "Could not determine owner." }
        let isoFormatter = ISO8601DateFormatter()
        var skipped = 0

        var lines: [String] = []
        for entry in limited {
            guard let root = rootsByUUID[entry.rootUUID] else {
                skipped += 1
                continue
            }
            let isMe = root.senderId == owner.id
            let sender = isMe ? "Me" : (root.senderAlias ?? "Unknown")
            let preview = root.getMessageContentPreview(owner: owner, contact: nil, includeSender: false)
            let lastActivityStr = isoFormatter.string(from: entry.lastActivity)
            lines.append(
                "[\(sender)] root_uuid=\(entry.rootUUID) replies=\(entry.replyCount) last_active=\(lastActivityStr): \(preview)"
            )
        }

        print("AIAgent read_threads: chat=\(chatName) limit=\(limit) found=\(grouped.count) skipped=\(skipped) capHit=\(hitCap)")

        var output = "Threads in '\(chatName)' (most recently active first):\n" + lines.joined(separator: "\n")
        if skipped > 0 {
            output += "\n\(skipped) more thread\(skipped == 1 ? "" : "s") were skipped because their first message isn't on this device."
        }
        if hitCap {
            output += "\n(only the most recent 5000 threaded messages were scanned)"
        }
        return output
    }
}
