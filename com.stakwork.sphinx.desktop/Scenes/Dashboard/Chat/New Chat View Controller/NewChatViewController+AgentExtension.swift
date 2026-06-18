import Foundation

extension NewChatViewController {

    // MARK: - Agent Processing Bar

    func setupAgentProcessingBar() {
        guard isAgentChat else { return }
        let bar = AgentProcessingBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: chatBottomView.topAnchor),
            heightConstraint
        ])
        agentBarHeightConstraint = heightConstraint
        agentProcessingBar = bar
    }

    func showAgentProcessingBar() {
        guard let bar = agentProcessingBar,
              let heightConstraint = agentBarHeightConstraint,
              heightConstraint.constant == 0 else { return }
        heightConstraint.constant = 32
        chatScrollView.contentInsets.bottom += 32
        bar.startAnimating()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            view.layoutSubtreeIfNeeded()
        }
        // 5-minute auto-dismiss timeout
        agentProcessingBarTimer?.invalidate()
        agentProcessingBarTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.hideAgentProcessingBar() }
        }
    }

    func hideAgentProcessingBar() {
        agentProcessingBarTimer?.invalidate()
        agentProcessingBarTimer = nil
        guard let bar = agentProcessingBar,
              let heightConstraint = agentBarHeightConstraint,
              heightConstraint.constant > 0 else { return }
        heightConstraint.constant = 0
        chatScrollView.contentInsets.bottom = max(0, chatScrollView.contentInsets.bottom - 32)
        bar.stopAnimating()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Agent Message Handling

    func handleAgentMessage(text: String, completion: @escaping (Bool) -> ()) {
        guard let chat = self.chat, let owner = self.owner else {
            completion(false)
            return
        }
        chatBottomView.resetReplyView()
        ChatTrackingHandler.shared.deleteReplyableMessage(with: chat.id)

        // Insert outgoing message
        let outgoing = TransactionMessage(context: CoreDataManager.sharedManager.persistentContainer.viewContext)
        outgoing.id = SphinxOnionManager.sharedInstance.uniqueIntHashFromString(stringInput: UUID().uuidString)
        outgoing.type = TransactionMessage.TransactionMessageType.message.rawValue
        outgoing.status = TransactionMessage.TransactionMessageStatus.received.rawValue
        outgoing.senderId = owner.id
        outgoing.receiverId = AIAgentManager.agentLocalId
        outgoing.messageContent = text
        outgoing.date = Date()
        outgoing.seen = true
        outgoing.encrypted = false
        outgoing.push = false
        outgoing.chat = chat
        chat.setLastMessage(outgoing)
        CoreDataManager.sharedManager.saveContext()
        completion(true)
//        showAgentProcessingBar()

        Task {
            let reply = await AIAgentManager.sharedInstance.chat(text)
            await MainActor.run { self.insertAgentReply(reply) }
        }
    }

    func insertIntroMessageIfNeeded() {
        guard isAgentChat,
              let chat = self.chat,
              let owner = self.owner,
              chat.lastMessage == nil else { return }

        let introText: String
        if AIAgentManager.sharedInstance.isConfigured {
            introText = """
👋 Hi! I'm your Sphinx AI assistant. Here's what I can do:

• 📖 Read recent or unread messages from any contact or tribe
• 👥 List all your contacts and tribes
• 👤 View and update your profile (nickname, tip amount)
• ✅ Mark chats as read
• 🔗 Connect with new users
• 🏕️ Create new tribes
• 🔍 Search the web for current info
• 🪵 Read and analyze app logs (filter by time, level, or keyword)
• 🤖 Ask Jamie anything about your org — features, tasks, codebase, project status
• 🐝 Browse, search & manage Hive workspaces, features, and tasks
"""
        } else {
            introText = "👋 Welcome to Sphinx AI! To get started, go to Profile → Configure AI Agent and enter your Anthropic or OpenAI API key."
        }

        let intro = TransactionMessage(context: CoreDataManager.sharedManager.persistentContainer.viewContext)
        intro.id = SphinxOnionManager.sharedInstance.uniqueIntHashFromString(stringInput: UUID().uuidString)
        intro.type = TransactionMessage.TransactionMessageType.message.rawValue
        intro.status = TransactionMessage.TransactionMessageStatus.received.rawValue
        intro.senderId = AIAgentManager.agentLocalId
        intro.receiverId = owner.id
        intro.messageContent = introText
        intro.date = Date()
        intro.seen = false
        intro.encrypted = false
        intro.push = false
        intro.chat = chat
        chat.seen = false
        chat.setLastMessage(intro)
        CoreDataManager.sharedManager.saveContext()

        AIAgentManager.sharedInstance.appendAssistantMessage(introText)
    }

    func insertAgentReply(_ text: String) {
        hideAgentProcessingBar()
        guard let chat = self.chat, let owner = self.owner else { return }
        let incoming = TransactionMessage(context: CoreDataManager.sharedManager.persistentContainer.viewContext)
        incoming.id = SphinxOnionManager.sharedInstance.uniqueIntHashFromString(stringInput: UUID().uuidString)
        incoming.type = TransactionMessage.TransactionMessageType.message.rawValue
        incoming.status = TransactionMessage.TransactionMessageStatus.received.rawValue
        incoming.senderId = AIAgentManager.agentLocalId
        incoming.receiverId = owner.id
        incoming.messageContent = text
        incoming.date = Date()
        incoming.seen = false
        incoming.encrypted = false
        incoming.push = false
        incoming.chat = chat
        chat.seen = false
        chat.setLastMessage(incoming)
        CoreDataManager.sharedManager.saveContext()
        NotificationCenter.default.post(name: .shouldReloadChatLists, object: nil, userInfo: ["chat-ids": [chat.id]])
    }
}
