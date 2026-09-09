//
//  StrutTranscript.swift
//  com.stakwork.sphinx.desktop
//
//  Pure accumulator for live (partial) and committed (final) dictation text.
//  No UI wiring — consumers read `committedText` / `liveText`.
//

import Foundation

struct StrutTranscriptState: Equatable, Sendable {

    private(set) var committedText: String = ""
    private(set) var liveText: String = ""

    /// Replaces the current live text. Never appends.
    mutating func apply(partial: String) {
        liveText = partial
    }

    /// Commits `final` and returns the full committed text.
    /// Sequential finals are joined by a single space, except punctuation-only
    /// finals (empty after stripping punctuation ∪ whitespace), which glue
    /// directly onto the previous committed word.
    @discardableResult
    mutating func apply(final: String) -> String {
        liveText = ""

        if isPunctuationOnly(final) {
            let glued = final.trimmingCharacters(in: .whitespaces)
            committedText += glued
        } else if committedText.isEmpty {
            committedText = final
        } else {
            committedText += " " + final
        }

        return committedText
    }

    private func isPunctuationOnly(_ text: String) -> Bool {
        var stripped = CharacterSet.punctuationCharacters
        stripped.formUnion(.whitespaces)
        return text.trimmingCharacters(in: stripped).isEmpty
    }
}
