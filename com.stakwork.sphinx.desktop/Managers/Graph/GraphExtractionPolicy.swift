//
//  GraphExtractionPolicy.swift
//  sphinx
//
//  Pure rules deciding whether a finished agent turn is sent to the graph extraction
//  model call, plus the privacy switch. See docs/graph-extraction.md.
//
import Foundation

enum GraphExtractionPolicy {

    /// Rule (keep in sync with docs/graph-extraction.md). Extract only if ALL hold:
    /// 1. the turn did not fail (error path -> skip);
    /// 2. the user text is not empty;
    /// 3. it is not a greeting / small talk: every word of the user text is a small-talk word
    ///    ("hi", "thanks", "how are you", "ok", ...);
    /// 4. if the turn used tools, the user text must contain an explicit personal-fact cue
    ///    ("my name is", "i live", "my wife", ...). Tool-only requests ("read my messages
    ///    from Bob") carry no personal content and are skipped.
    /// Turns without tools that pass 1-3 are extracted; the model may still return nothing.
    static func shouldExtract(userText: String, toolNames: [String], didFail: Bool) -> Bool {
        if didFail { return false }

        let normalized = normalizeText(userText)
        let words = normalized.split(separator: " ").map(String.init)
        if words.isEmpty { return false }

        if words.allSatisfy({ smallTalkWords.contains($0) }) { return false }

        if !toolNames.isEmpty {
            let padded = " " + normalized + " "
            return personalCues.contains { padded.contains(" \($0) ") }
        }
        return true
    }

    /// Lowercase, curly apostrophes -> straight, punctuation -> space, whitespace collapsed.
    static func normalizeText(_ text: String) -> String {
        let straight = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        let scalars = straight.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" { return Character(scalar) }
            return " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static let smallTalkWords: Set<String> = [
        "hi", "hello", "hey", "hiya", "yo", "sup", "howdy", "thanks", "thank", "thx", "ty", "you",
        "ok", "okay", "k", "cool", "great", "nice", "good", "morning", "afternoon", "evening",
        "night", "bye", "goodbye", "later", "see", "how", "are", "u", "doing", "whats", "what's",
        "up", "please", "yes", "no", "yeah", "yep", "nope", "sure", "lol", "haha", "there", "again",
        "much", "very", "so", "a", "lot", "awesome", "perfect", "got", "it", "welcome", "np", "gm", "gn"
    ]

    static let personalCues: [String] = [
        "my name is", "i live", "i work", "i moved", "i was born", "i'm from", "i am from",
        "i'm a", "i am a", "i'm working", "i am working", "i like", "i love", "i prefer",
        "i own", "i have a", "i have two", "i have three", "i'm interested", "i am interested",
        "remember that", "my wife", "my husband", "my partner", "my girlfriend", "my boyfriend",
        "my friend", "my brother", "my sister", "my mother", "my father", "my mom", "my dad",
        "my son", "my daughter", "my boss", "my colleague", "my dog", "my cat"
    ]
}

/// Privacy switch for graph extraction. Default ON. A missing bool key reads `false` in
/// UserDefaults, so the default is registered at launch AND `isEnabled` treats a missing
/// key as true.
enum GraphExtractionSettings {

    static let enabledKey = "graphExtractionEnabled"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [enabledKey: true])
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        return (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }
}
