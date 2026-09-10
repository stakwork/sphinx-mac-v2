//
//  ComposerDictationDisplay.swift
//  com.stakwork.sphinx.desktop
//
//  Pure helper that assembles live composer-field text during dictation:
//  snapshot prefix + committed finals + current (replaced) partial.
//  No AppKit / NSView dependency.
//

import Foundation

struct ComposerDictationDisplay: Equatable, Sendable {

    private(set) var prefix: String = ""
    private var transcript = StrutTranscriptState()

    /// Snapshots the text already in the composer at successful dictation start.
    mutating func setPrefix(_ prefix: String) {
        self.prefix = prefix
    }

    /// Replaces the current in-progress partial. Never stacks.
    mutating func apply(partial: String) {
        transcript.apply(partial: partial)
    }

    /// Commits a final fragment into the running transcript.
    mutating func apply(final: String) {
        transcript.apply(final: final)
    }

    /// Prefix glued to committed finals plus the current live partial.
    var fieldText: String {
        glue(prefix, glue(transcript.committedText, transcript.liveText))
    }

    /// Committed finals only — no prefix, no live partial. Correction baseline.
    var committedText: String { transcript.committedText }

    /// Clears prefix and transcript state for a new dictation session.
    mutating func reset() {
        prefix = ""
        transcript = StrutTranscriptState()
    }

    // MARK: - Glue

    /// Joins `left` and `right` with a space, except when `right`'s first
    /// meaningful token is punctuation-only (same rule as
    /// `StrutTranscriptState.apply(final:)`), in which case they are glued
    /// with no space. Empty sides are omitted so an empty prefix never
    /// produces a leading space.
    private func glue(_ left: String, _ right: String) -> String {
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        if isPunctuationOnly(firstMeaningfulToken(right)) {
            return left + right.trimmingCharacters(in: .whitespaces)
        }
        return left + " " + right
    }

    private func firstMeaningfulToken(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let token = trimmed.split(whereSeparator: { $0.isWhitespace }).first else {
            return trimmed
        }
        return String(token)
    }

    /// Same rule as `StrutTranscriptState.isPunctuationOnly`.
    private func isPunctuationOnly(_ text: String) -> Bool {
        var stripped = CharacterSet.punctuationCharacters
        stripped.formUnion(.whitespaces)
        return text.trimmingCharacters(in: stripped).isEmpty
    }
}
