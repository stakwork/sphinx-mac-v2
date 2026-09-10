//
//  NewChatViewModel+DictationExtension.swift
//  Sphinx
//
//  Session ownership for composer dictation: phase machine, generation
//  token, occupancy, and generation-scoped client callbacks.
//

import Foundation

extension NewChatViewModel {

    enum DictationUserMessage {
        static let permissionDenied =
            "Microphone permission was denied. Enable it in System Settings to use dictation."
        static let microphoneInUse =
            "The microphone is in use. Stop the voice note, call, or other dictation session and try again."
        static let sttUnavailable =
            "Speech-to-text is unavailable. Check that Strut is running and try again."
    }

    func toggleDictation() {
        switch dictationPhase {
        case .idle:
            startConnecting()
        case .connecting:
            cancelConnecting()
        case .dictating:
            Task { await self.stopDictationSession(reason: "user toggle") }
        case .stopping:
            break
        }
    }

    func cancelDictationForLeave() async {
        await stopDictationSession(reason: "leave")
    }

    func stopDictationBeforeSend() async {
        await stopDictationSession(reason: "send")
    }

    func stopDictationBeforeVoiceNote() async {
        await stopDictationSession(reason: "voice note")
    }

    // MARK: - Connecting

    private func startConnecting() {
        dictationGeneration += 1
        let generation = dictationGeneration
        setPhase(.connecting, generation: generation)

        dictationConnectingTask = Task { [weak self] in
            let result = await StrutConnection.shared.readyConnection()
            guard let self else { return }
            if Task.isCancelled {
                AppLogger.shared.log(
                    level: .info,
                    message: "[StrutDictation] connecting cancel generation=\(generation) (health-check Task cancelled before a client exists)"
                )
                return
            }
            self.handleReadyResult(result, generation: generation)
        }
    }

    private func cancelConnecting() {
        let generation = dictationGeneration
        AppLogger.shared.log(
            level: .info,
            message: "[StrutDictation] connecting cancel generation=\(generation) (health-check Task cancelled before a client exists)"
        )
        dictationConnectingTask?.cancel()
        dictationConnectingTask = nil
        dictationGeneration += 1
        releaseOccupancyIfHeld()
        setPhase(.idle, generation: dictationGeneration)
        onDictationActiveChanged?(false)
    }

    private func handleReadyResult(
        _ result: Result<StrutReadyConnection, StrutNotReady>,
        generation: Int
    ) {
        guard generation == dictationGeneration else {
            logIgnoredStaleCallback(kind: "ready", generation: generation)
            return
        }
        guard dictationPhase == .connecting else {
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] ignored ready callback phase=\(Self.describe(dictationPhase)) generation=\(generation)"
            )
            return
        }

        switch result {
        case .failure:
            failToIdle(
                userMessage: DictationUserMessage.sttUnavailable,
                generation: generation
            )
        case .success(let ready):
            beginDictating(ready: ready, generation: generation)
        }
    }

    private func beginDictating(
        ready: StrutReadyConnection,
        generation: Int
    ) {
        guard generation == dictationGeneration, dictationPhase == .connecting else {
            logIgnoredStaleCallback(kind: "start", generation: generation)
            return
        }

        guard StrutConnection.tryAcquireDictationOccupancy() else {
            failToIdle(
                userMessage: DictationUserMessage.microphoneInUse,
                generation: generation
            )
            return
        }
        holdsDictationOccupancy = true
        dictationSessionId = UUID().uuidString

        dictationConnectingTask = nil

        dictationDisplay.reset()
        dictationDisplay.setPrefix(dictationPrefixProvider?() ?? "")

        // Extract plain strings on the MainActor before any Task hop —
        // never pass NSManagedObject / UserContact across an actor boundary.
        let contactNicknames = dictationContactNicknames()
        let contactHotwords = StrutHotwordList.build(from: contactNicknames)
        let startHotwords = StrutHotwordList.build(
            from: contactNicknames + dictationChatAliases()
        )

        clearClientHandlers()
        let client = StrutDictationClient(
            ready: ready,
            session: dictationSessionId,
            hotwords: startHotwords
        )
        bindClient(client, generation: generation)
        dictationClient = client
        client.start()

        seedHotwordsIfNeeded(contactHotwords, ready: ready)

        setPhase(.dictating, generation: generation)
        onDictationActiveChanged?(true)
        onDictationTextChanged?(dictationDisplay.fieldText)
    }

    /// Confirmed, non-owner, non-agent, non-tribe nicknames. Pin-hidden
    /// contacts (`pin != nil`) are excluded. `UserContact.chatList()` already
    /// drops owner/fromGroup rows; the snapshot filter is the testable gate.
    private func dictationContactNicknames() -> [String] {
        let snapshots = UserContact.chatList().map { contact in
            StrutHotwordList.Contact(
                nickname: contact.nickname,
                isConfirmed: contact.isConfirmed(),
                isOwner: contact.isOwner,
                isAgent: contact.isAgent,
                fromGroup: contact.fromGroup,
                pin: contact.pin
            )
        }
        return StrutHotwordList.nicknames(from: snapshots)
    }

    private func dictationChatAliases() -> [String] {
        (chat?.aliasesAndPics ?? []).map { $0.0 }
    }

    /// Process-once PUT of the contact list (no chat-scoped aliases).
    /// Fire-and-forget after `client.start()` so it never delays the mic.
    private func seedHotwordsIfNeeded(
        _ words: [String],
        ready: StrutReadyConnection
    ) {
        guard StrutConnection.tryMarkHotwordsSeeded() else { return }
        Task {
            await StrutLearningClient.shared.putHotwords(
                name: "sphinx",
                words: words,
                ready: ready
            )
        }
    }

    // MARK: - Stop / fail / occupancy

    private func stopDictationSession(reason: String) async {
        let current = dictationPhase
        if current == .idle {
            return
        }

        dictationConnectingTask?.cancel()
        dictationConnectingTask = nil

        let discardCallbacks = reason == "leave"

        if current == .connecting {
            dictationGeneration += 1
            let generation = dictationGeneration
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] connecting cancel generation=\(generation) reason=\(reason)"
            )
            releaseOccupancyIfHeld()
            clearClientHandlers()
            dictationClient = nil
            setPhase(.idle, generation: generation)
            onDictationActiveChanged?(false)
            return
        }

        // Leave discards in-flight transcript writes immediately. Send / toggle
        // keep handlers through stop so a trailing final can still land.
        if discardCallbacks {
            dictationGeneration += 1
            clearClientHandlers()
        }

        setPhase(.stopping, generation: dictationGeneration)
        onDictationActiveChanged?(false)

        let client = dictationClient
        await client?.stopAndWait()
        clearClientHandlers()
        if !discardCallbacks {
            dictationGeneration += 1
        }
        dictationClient = nil
        releaseOccupancyIfHeld()
        setPhase(.idle, generation: dictationGeneration)
    }

    private func failToIdle(userMessage: String, generation: Int) {
        guard generation == dictationGeneration else {
            logIgnoredStaleCallback(kind: "fail", generation: generation)
            return
        }
        dictationConnectingTask?.cancel()
        dictationConnectingTask = nil
        clearClientHandlers()
        dictationClient = nil
        dictationGeneration += 1
        releaseOccupancyIfHeld()
        setPhase(.idle, generation: dictationGeneration)
        onDictationActiveChanged?(false)
        onDictationFailed?(userMessage)
    }

    private func releaseOccupancyIfHeld() {
        guard holdsDictationOccupancy else { return }
        holdsDictationOccupancy = false
        StrutConnection.releaseDictationOccupancy()
    }

    private func clearClientHandlers() {
        dictationClient?.onPartial = nil
        dictationClient?.onFinal = nil
        dictationClient?.onError = nil
        dictationClient?.onReady = nil
    }

    // MARK: - Client callbacks

    private func bindClient(_ client: StrutDictationClient, generation: Int) {
        client.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.handlePartial(text, generation: generation)
            }
        }
        client.onFinal = { [weak self] text, _ in
            Task { @MainActor [weak self] in
                self?.handleFinal(text, generation: generation)
            }
        }
        client.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleClientError(message, generation: generation)
            }
        }
    }

    private func handlePartial(_ text: String, generation: Int) {
        guard generation == dictationGeneration else {
            logIgnoredStaleCallback(kind: "partial", generation: generation)
            return
        }
        dictationDisplay.apply(partial: text)
        onDictationTextChanged?(dictationDisplay.fieldText)
    }

    private func handleFinal(_ text: String, generation: Int) {
        guard generation == dictationGeneration else {
            logIgnoredStaleCallback(kind: "final", generation: generation)
            return
        }
        dictationDisplay.apply(final: text)
        onDictationTextChanged?(dictationDisplay.fieldText)
    }

    private func handleClientError(_ message: String, generation: Int) {
        guard generation == dictationGeneration else {
            logIgnoredStaleCallback(kind: "error", generation: generation)
            return
        }
        if dictationPhase == .stopping {
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] ignoring stop-timeout error generation=\(generation)"
            )
            return
        }
        if message == "stopped without a final response" {
            AppLogger.shared.log(
                level: .info,
                message: "[StrutDictation] ignoring user-initiated stop timeout generation=\(generation)"
            )
            return
        }
        failToIdle(
            userMessage: mapDictationFailure(message),
            generation: generation
        )
    }

    func mapDictationFailure(_ reason: String) -> String {
        let lowered = reason.lowercased()
        if lowered.contains("permission") {
            return DictationUserMessage.permissionDenied
        }
        if lowered.contains("in use") || lowered.contains("busy") {
            return DictationUserMessage.microphoneInUse
        }
        return DictationUserMessage.sttUnavailable
    }

    // MARK: - Logging

    private func setPhase(_ phase: DictationPhase, generation: Int) {
        let previous = dictationPhase
        dictationPhase = phase
        AppLogger.shared.log(
            level: .info,
            message: "[StrutDictation] phase \(Self.describe(previous)) → \(Self.describe(phase)) generation=\(generation)"
        )
    }

    private func logIgnoredStaleCallback(kind: String, generation: Int) {
        AppLogger.shared.log(
            level: .info,
            message: "[StrutDictation] ignored stale-generation \(kind) callback generation=\(generation) current=\(dictationGeneration)"
        )
    }

    private static func describe(_ phase: DictationPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .dictating: return "dictating"
        case .stopping: return "stopping"
        }
    }
}
