//
//  String.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 05/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import AppKit

extension String {
    
    var localized: String {
        get {
            return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: "")
        }
    }
    
    var withoutBreaklines: String {
        get {
            return self.replacingOccurrences(of: "\n", with: " ")
        }
    }
    
    var nsRange : NSRange {
        return NSRange(self.startIndex..., in: self)
    }
    
    var length: Int {
      return count
    }

    subscript (i: Int) -> String {
      return self[i ..< i + 1]
    }

    func substring(fromIndex: Int) -> String {
      return self[fromIndex ..< length]
    }

    func substring(toIndex: Int) -> String {
      return self[0 ..< toIndex]
    }
    
    func charAt(index: Int) -> Character {
        let i = String.Index(utf16Offset: index, in: self)
        return self[i]
    }
    
    func substring(fromIndex: Int, toIndex: Int) -> String {
      return self[fromIndex ..< toIndex]
    }

    func substring(toIndexIncluded: Int) -> String {
        let end = String.Index(utf16Offset: toIndexIncluded, in: self)
        return String(self[...end])
    }
    
    func substring(fromIndex: Int, toIndexIncluded: Int) -> String {
      return self[fromIndex ..< toIndexIncluded]
    }
    
    mutating func insert(string:String,ind:Int) {
        self.insert(contentsOf: string, at:self.index(self.startIndex, offsetBy: ind) )
    }

    subscript (r: Range<Int>) -> String {
      let range = Range(uncheckedBounds: (lower: max(0, min(length, r.lowerBound)),
                                          upper: min(length, max(0, r.upperBound))))
      let start = index(startIndex, offsetBy: range.lowerBound)
      let end = index(start, offsetBy: range.upperBound - range.lowerBound)
      return String(self[start ..< end])
    }
    
    func starts(with prefixes: [String]) -> Bool {
        for prefix in prefixes where starts(with: prefix) {
            return true
        }
        return false
    }
    
    func trunc(length: Int) -> String {
        return (self.count > length) ? String(self.prefix(length)) : self
    }
    
    func toJSON() -> Any? {
        guard let data = self.data(using: .utf8, allowLossyConversion: false) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .mutableContainers)
    }
    
    func fixInvoiceString() -> String {
        var fixedInvoice = self
        
        let prefixes = PaymentRequestDecoder.prefixes
        for prefix in prefixes {
            if self.contains(prefix) {
                if let index = self.range(of: prefix)?.lowerBound {
                    let indexInt = index.utf16Offset(in: self)
                    fixedInvoice = self.substring(fromIndex: indexInt, toIndex: self.length)
                }
            }
        }
        return fixedInvoice
    }
    
    var fixedRestoreCode : String {
        get {
            let codeWithoutSpaces = self.replacingOccurrences(of: "\\n", with: "")
                                        .replacingOccurrences(of: "\\r", with: "")
                                        .replacingOccurrences(of: "\\s", with: "")
                                        .replacingOccurrences(of: " ", with: "")
            
            let fixedCode = codeWithoutSpaces.filter("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".contains)
            
            return fixedCode
        }
    }
    
    var shareContactDeepLink : String {
        get {
            return "sphinx.chat://?action=share_contact&pubKey=\(self)"
        }
    }
    
    var callLinkDeepLink : String {
        get {
            return "sphinx.chat://?action=call&link=\(self)"
        }
    }
    
    func removeProtocol() -> String {
        return self.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
    }
    
    func decodeUrl() -> String? {
        return self.removingPercentEncoding
    }
    
    var isRelayQRCode : Bool {
        get {
            return self.base64Decoded?.starts(with: "ip::") ?? false
        }
    }
    
    var isSwarmConnectCode : Bool {
        get {
            return self.contains("connect::")
        }
    }
    
    var isSwarmClaimCode : Bool {
        get {
            return self.contains("claim::")
        }
    }
    
    func getIPAndPassword() -> (String?, String?) {
        if let decodedString = self.base64Decoded, decodedString.starts(with: "ip::") {
            let stringWithoutPrefix = decodedString.replacingOccurrences(of: "ip::", with: "")
            let items = stringWithoutPrefix.components(separatedBy: "::")
            
            if items.count == 2 {
                return (items[0], items[1])
            }
        }
        return (nil, nil)
    }
    
    var isRestoreKeysString : Bool {
        get {
            return self.base64Decoded?.starts(with: "keys::") ?? false
        }
    }
    
    func getRestoreKeys() -> String? {
        if let decodedString = self.base64Decoded, decodedString.starts(with: "keys::") {
            let stringWithoutPrefix = decodedString.replacingOccurrences(of: "keys::", with: "")
            return stringWithoutPrefix
        }
        return nil
    }
    
    func trim() -> String {
        return self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    func markdownTrim() -> String {
        if self.isEmpty {
            return self
        }
        
        var trimmedString = self
        let zeroWidthSpace = "\u{200B}"

        ///Replace new line with empty space if it starts with highlight char and new line
        if self.starts(with: "\(zeroWidthSpace)\n") {
            trimmedString = trimmedString.replacingOccurrences(
                of: "\(zeroWidthSpace)\n",
                with: "\(zeroWidthSpace)\(zeroWidthSpace)",
                range: Range(NSRange(location: 0, length: 2), in: trimmedString)
            )
        }
        ///Replace new line with empty space if it starts with bold chars and new line
        if self.starts(with: "\(zeroWidthSpace)\(zeroWidthSpace)\n") {
            trimmedString = trimmedString.replacingOccurrences(
                of: "\(zeroWidthSpace)\(zeroWidthSpace)\n",
                with: "\(zeroWidthSpace)\(zeroWidthSpace)\(zeroWidthSpace)",
                range: Range(NSRange(location: 0, length: 3), in: trimmedString)
            )
        }
        ///Replace new line with empty space if it ends with new line and highlight char
        if self.hasSuffix("\n\(zeroWidthSpace)") {
            trimmedString = trimmedString.replacingOccurrences(
                of: "\n\(zeroWidthSpace)",
                with: "\(zeroWidthSpace)\(zeroWidthSpace)",
                range: Range(NSRange(location: self.length - 2, length: 2), in: trimmedString)
            )
        }
        ///Replace new line with empty space if it ends with new line and bold chars
        if self.hasSuffix("\n\(zeroWidthSpace)\(zeroWidthSpace)") {
            trimmedString = trimmedString.replacingOccurrences(
                of: "\n\(zeroWidthSpace)\(zeroWidthSpace)",
                with: "\(zeroWidthSpace)\(zeroWidthSpace)\(zeroWidthSpace)", 
                range: Range(NSRange(location: self.length - 3, length: 3), in: trimmedString)
            )
        }
        return trimmedString
    }
    
    func isEncryptedString() -> Bool {
        if let _ = Data(base64Encoded: self), self.hasSuffix("=") {
            return true
        }
        return false
    }
    
    func getBytesLength() -> Int {
        return self.utf8.count
    }
    
    func isValidLengthMemo() -> Bool {
        return getBytesLength() <= 639
    }
    
    var isValidURL: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            return match.range.length == self.utf16.count
        } else {
            return false
        }
    }
    
    var percentEscaped: String? {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
    }
    
    var percentNotEscaped: String? {
        return NSString(string: self).removingPercentEncoding
    }
    
    var fixedAlias: String {
        let ACCEPTABLE_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
        var fixedAlias = ""
        
        for ch in self.replacingOccurrences(of: " ", with: "_") {
            if (ACCEPTABLE_CHARACTERS.contains(ch)) {
                fixedAlias.append(ch)
            }
        }
        return fixedAlias
    }
    
    var stringLinks: [NSTextCheckingResult] {
        if !self.contains(".") {
            return []
        }
        
        let textWithoutMarkdown = self.removingMarkdownDelimiters
        let types: NSTextCheckingResult.CheckingType = [.link]
        let detector = try? NSDataDetector(types: types.rawValue)
        
        let matches = detector!.matches(
            in: textWithoutMarkdown,
            options: .reportCompletion,
            range: NSMakeRange(0, textWithoutMarkdown.utf16.count)
        )
        
        return matches

    }
    
    var pubKeyMatches: [NSTextCheckingResult] {
        let textWithoutMarkdown = self.removingMarkdownDelimiters
        let pubkeyRegex = try? NSRegularExpression(pattern: "\\b[A-F0-9a-f]{66}\\b")
        let virtualPubkeyRegex = try? NSRegularExpression(pattern: "\\b[A-F0-9a-f]{66}_[A-F0-9a-f]{66}_[0-9]+\\b")
        
        let virtualPubkeyResults = virtualPubkeyRegex?.matches(
            in: textWithoutMarkdown,
            range: NSRange(textWithoutMarkdown.startIndex..., in: textWithoutMarkdown)
        ) ?? []
        
        let pubkeyResults = pubkeyRegex?.matches(
            in: textWithoutMarkdown,
            range: NSRange(textWithoutMarkdown.startIndex..., in: textWithoutMarkdown)
        ) ?? []
        
        return virtualPubkeyResults + pubkeyResults
    }
    
    var mentionMatches: [NSTextCheckingResult] {
        let textWithoutMarkdown = self.removingMarkdownDelimiters
        let mentionRegex = try? NSRegularExpression(pattern: "\\B@[^\\s]+")
        
        return mentionRegex?.matches(
            in: textWithoutMarkdown,
            range: NSRange(textWithoutMarkdown.startIndex..., in: textWithoutMarkdown)
        ) ?? []
    }
    
    var highlightedMatches: [NSTextCheckingResult] {
        if !self.contains("`") {
            return []
        }
        let highlightedRegex = try? NSRegularExpression(pattern: "`(.*?)`", options: .dotMatchesLineSeparators)
        return highlightedRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []
    }
    
    var boldMatches: [NSTextCheckingResult] {
        if !self.contains("**") {
            return []
        }
        let highlightedRegex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*", options: .dotMatchesLineSeparators)
        return highlightedRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []
    }
    
    var itemsMatches: [NSTextCheckingResult] {
        if !self.contains("-") {
            return []
        }
        let highlightedRegex = try? NSRegularExpression(pattern: "(?<=^|\n)([\u{200B}]*)(-)(?!-)", options: .dotMatchesLineSeparators)
        return highlightedRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []
    }
    
    var linkMarkdownMatches: [(NSTextCheckingResult, String, String, Bool)] {
        if !self.contains("[") && self.contains("(") {
            return []
        }
        
        var results: [(NSTextCheckingResult, String, String, Bool)] = []
        
        let linkMarkdownPattern = #"!\[([^\]]+)\]\((http[s]?:\/\/[^\s\)]+)\)"#
        let linkMarkdownRegex = try? NSRegularExpression(pattern: linkMarkdownPattern)
        let matches = linkMarkdownRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []
        
        for match in matches {
            if let result = getMatchAndStringsFrom(match: match, hasExclamationMark: true) {
                results.append(result)
            }
        }
        
        let linkMarkdownPattern2 = #"\[([^\]]+)\]\((http[s]?:\/\/[^\s\)]+)\)"#
        let linkMarkdownRegex2 = try? NSRegularExpression(pattern: linkMarkdownPattern2)
        let matches2 = linkMarkdownRegex2?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []
        
        for match in matches2 {
            if let result = getMatchAndStringsFrom(match: match, hasExclamationMark: false) {
                results.append(result)
            }
        }
        
        return results
    }
    
    func getMatchAndStringsFrom(
        match: NSTextCheckingResult,
        hasExclamationMark: Bool
    ) -> (NSTextCheckingResult, String, String, Bool)? {
        if let imageRange = Range(match.range(at: 1), in: self),
           let linkRange = Range(match.range(at: 2), in: self) {
            let imageText = String(self[imageRange])
            let linkText = String(self[linkRange])
            return (match, "\(imageText)", "\(linkText)", hasExclamationMark)
        }
        return nil
    }
    
    var removingMarkdownDelimiters: String {
        return self.trim().replacingHightlightedChars.replacingBoldDelimeterChars.replacingHyphensWithBullets.replacingMarkdownLinks.markdownTrim()
    }
    
    var replacingMarkdownLinks: String {
        if !self.contains("[") && self.contains("(") {
            return self
        }
        
        var adaptedString = self
        
        for (match, text, link, hasExclamationMark)  in linkMarkdownMatches {

            let adaptedRange = NSRange(location: match.range.location, length: match.range.length)
            let zeroWidthSpace = "\u{200B}"
            
            let prefixString = (hasExclamationMark) ? "\(zeroWidthSpace)\(zeroWidthSpace)" : "\(zeroWidthSpace)"
            let afterLinkChartsCount = 3 + link.count
            
            var suffixString = ""
            for _ in 0..<afterLinkChartsCount {
                suffixString += zeroWidthSpace
            }
            
            adaptedString = adaptedString.replacingOccurrences(
                of: hasExclamationMark ? "![\(text)](\(link))" : "[\(text)](\(link))",
                with: "\(prefixString)\(text)\(suffixString)",
                range: Range(adaptedRange, in: adaptedString)
            )
        }
        
        return adaptedString
    }
    
    var replacingHightlightedChars: String {
        if !self.contains("`") {
            return self
        }
        
        var adaptedString = self
        
        for match in highlightedMatches {
            
            let adaptedRange = NSRange(location: match.range.location, length: match.range.length)
            let zeroWidthSpace = "\u{200B}"
            
            adaptedString = adaptedString.replacingOccurrences(
                of: "`",
                with: zeroWidthSpace,
                range: Range(adaptedRange, in: adaptedString)
            )
        }
        
        return adaptedString
    }
    
    var replacingBoldDelimeterChars: String {
        if !self.contains("**") {
            return self
        }
        
        var adaptedString = self
        
        for match in boldMatches {
            
            let adaptedRange = NSRange(location: match.range.location, length: match.range.length)
            let zeroWidthSpace = "\u{200B}"
            
            adaptedString = adaptedString.replacingOccurrences(
                of: "*",
                with: zeroWidthSpace,
                range: Range(adaptedRange, in: adaptedString)
            )
        }
        
        return adaptedString
    }
    
    var replacingHyphensWithBullets: String {
        if !self.contains("-") {
            return self
        }
        
        var adaptedString = self
        
        for match in itemsMatches {
            
            let adaptedRange = NSRange(location: match.range.location, length: match.range.length)
            
            adaptedString = adaptedString.replacingOccurrences(
                of: "-",
                with: "•",
                range: Range(adaptedRange, in: adaptedString)
            )
        }
        
        return adaptedString
    }
    
    var stringFirstWebLink : (String, NSRange)? {
        if let range = self.stringLinks.first?.range {
            let matchString = (self as NSString).substring(with: range) as String
            return (matchString, range)
        }
        return nil
    }
    
    var stringFirstTribeLink : (String, NSRange)? {
        for link in self.stringLinks {
            let range = link.range
            let matchString = (self as NSString).substring(with: range) as String
            if matchString.starts(with: "sphinx.chat://?action=tribe") {
                return (matchString, range)
            }
        }
        return nil
    }
    
    var stringFirstPubKey : (String, NSRange)? {
        if let range = self.pubKeyMatches.first?.range {
            let matchString = (self as NSString).substring(with: range) as String
            return (matchString, range)
        }
        return nil
    }
    
    var stringFirstLink: String? {
        let firstWebLink = stringFirstWebLink
        let firstContactLink = stringFirstPubKey
        let firstTribeJoinLink = stringFirstTribeLink
        
        var ranges = [NSRange]()

        if let firstWebLinkRange = firstWebLink?.1 {
            ranges.append(firstWebLinkRange)
        }
        
        if let firstContactLinkRange = firstContactLink?.1 {
            ranges.append(firstContactLinkRange)
        }
        
        if let firstTribeJoinLinkRange = firstTribeJoinLink?.1 {
            ranges.append(firstTribeJoinLinkRange)
        }
        
        ranges = ChatHelper.removeDuplicatedContainedFrom(urlRanges: ranges)
        
        if let firstLinkRange = ranges.first {
            return (self as NSString).substring(with: firstLinkRange) as String
        }
        
        return nil
    }
    
    var hasLinks: Bool {
        if self.isCallLink {
            return false
        }
        
        if stringLinks.count == 0 {
            return false
        }
        
        for link in stringLinks {
            let matchString = (self as NSString).substring(with: link.range) as String
            if matchString.isValidEmail || matchString.starts(with: "sphinx.chat://") {
                return false
            }
        }
        return !hasTribeLinks && !hasPubkeyLinks
    }
    
    var hasTribeLinks: Bool {
        for link in stringLinks {
            let matchString = (self as NSString).substring(with: link.range) as String
            if matchString.starts(with: "sphinx.chat://?action=tribe") {
                return true
            }
        }
        return false
    }
    
    var hasPubkeyLinks: Bool {
        return pubKeyMatches.count > 0 && !hasTribeLinks
    }
    
    var isTribeJoinLink : Bool {
        get {
            return self.starts(with: "sphinx.chat://?action=tribe")
        }
    }
    
    var isTribeV2 : Bool {
        return self.contains("action=tribeV2") && self.contains("pubkey=")
    }
    
    var isPubKey : Bool {
        get {
            let pubkeyRegex = try? NSRegularExpression(pattern: "^[A-F0-9a-f]{66}$")
            return (pubkeyRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []).count > 0 || self.isVirtualPubKey
        }
    }
    
    var isRouteHint : Bool {
        get {
            let routeHintRegex = try? NSRegularExpression(pattern: "^[A-F0-9a-f]{66}_[0-9]+$")
            return (routeHintRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []).count > 0
        }
    }
    
    var isVirtualPubKey : Bool {
        get {
            let completePubkeyRegex = try? NSRegularExpression(pattern: "^[A-F0-9a-f]{66}_[A-F0-9a-f]{66}_[0-9]+$")
            return (completePubkeyRegex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []).count > 0
        }
    }
    
    var pubkeyComponents : (String, String) {
        get {
            let components = self.components(separatedBy: "_")
            if components.count >= 3 {
                return (components[0], self.replacingOccurrences(of: components[0] + "_", with: ""))
            }
            return (self, "")
        }
    }
    
    func withProtocol(protocolString: String) -> String {
        if !self.contains(protocolString) {
            let linkString = "\(protocolString)://\(self)"
            return linkString
        }
        return self
    }
     
    func isExistingContactPubkey() -> (Bool, UserContact?) {
        if let pubkey = self.stringFirstPubKey?.0 {
            let (pk, _) = pubkey.pubkeyComponents
            if let contact = UserContact.getContactWith(pubkey: pk), !contact.fromGroup {
               return (true, contact)
            }
            if let owner = UserContact.getOwner(), owner.publicKey == pk {
                return (true, owner)
            }
        }
        return (false, nil)
    }
    
    var isV2InviteCode : Bool{
        get {
            return self.starts(with: "sphinx.chat://?action=i&d")
        }
    }
    
    var isInviteCode : Bool {
        get {
            let regex = try? NSRegularExpression(pattern: "^[A-F0-9a-f]{40}$")
            return ((regex?.matches(in: self, range: NSRange(self.startIndex..., in: self)) ?? []).count > 0) || isV2InviteCode
        }
    }
    
    var isLNDInvoice : Bool {
        get {
            let prDecoder = PaymentRequestDecoder()
            prDecoder.decodePaymentRequest(paymentRequest: self)
            return prDecoder.isPaymentRequest()
        }
    }
    
    var isMessagesFetchResponse : Bool {
        return self.contains("/batch") 
    }
    
    var amountWithoutSpaces: String {
        return self.replacingOccurrences(of: " ", with: "")
    }
    
    var base64Decoded : String? {
        if let decodedData = Data(base64Encoded: self) {
            if let decodedString = String(data: decodedData, encoding: .utf8) {
                return decodedString
            }
        }
        return nil
    }
    
    var base64Encoded : String? {
        return Data(self.utf8).base64EncodedString()
    }
    
    var hexEncoded : String {
        let data = Data(self.utf8)
        let hexString = data.map{ String(format:"%02x", $0) }.joined()
        return hexString
    }
    
    var dataFromString : Data? {
        return Data(base64Encoded: self.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))
    }
    
    var urlSafe: String {
        return self.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    
    var nonBase64Data: Data? {
        get {
            var valid = self.count % 4 == 0
            var fixedString = self
            
            while (!valid) {
                fixedString = String(fixedString.dropLast())
                valid = fixedString.count % 4 == 0
            }
            let fixedChallenge = fixedString
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            
            if let challengeData = Data(base64Encoded: fixedChallenge) {
                return challengeData
            }
            return nil
        }
    }
    
    var lowerClean : String {
        return self.trim().lowercased()
    }
    
    var callServer : String {
        if let range = self.lowerClean.range(of: "sphinx.call.") {
            let room = self.lowerClean[..<range.lowerBound]
            return String(room)
        }
        return self.lowerClean
    }
    
    var callRoom : String {
        if let range = self.lowerClean.range(of: "sphinx.call.") {
            let endIndex = self.index(of: "#") ?? self.endIndex
            let roomWithParams = String(self.lowerClean[range.lowerBound..<endIndex])
            let queryEndIndex = roomWithParams.index(of: "?") ?? roomWithParams.endIndex
            let room = roomWithParams.lowerClean[roomWithParams.startIndex..<queryEndIndex]
            return String(room)
        }
        return self.lowerClean
    }
    
    var isJitsiCallLink: Bool {
        get {
            return self.lowerClean.starts(with: "http") && self.lowerClean.contains(API.kJitsiCallServer)
        }
    }
    
    var isLiveKitCallLink: Bool {
        get {
            return self.lowerClean.starts(with: "http") && self.lowerClean.contains(API.kLiveKitCallServer)
        }
    }
    
    var liveKitRoomName: String? {
        get {
            let elements = self.components(separatedBy: "rooms/")
            if elements.count > 1 {
                return (elements[1].components(separatedBy: "#").first)?.components(separatedBy: "?").first
            }
            return nil
        }
    }
    
    var isCallLink: Bool {
        get {
            return self.lowerClean.starts(with: "http") && self.lowerClean.contains(TransactionMessage.kCallRoomName)
        }
    }
    
    var isGiphy: Bool {
        get {
            if self.starts(with: GiphyHelper.kPrefix) {
                if let _ = self.replacingOccurrences(of: GiphyHelper.kPrefix, with: "").base64Decoded {
                    return true
                }
            }
            return false
        }
    }
    
    var isPodcastComment: Bool {
        get {
            return self.starts(with: PodcastFeed.kClipPrefix)
        }
    }
    
    var isPodcastBoost: Bool {
        get {
            return self.starts(with: PodcastFeed.kBoostPrefix)
        }
    }
    
    var isYouTubeRSSFeed: Bool {
        contains("www.youtube.com")
    }
    
    var podcastId: Int {
        get {
            let components = self.components(separatedBy: ":")
            if components.count > 1 {
                let value = components[1]
                
                if let id = Int(value) {
                    return id
                }
            }
            return -1
        }
    }
    
    var tribeUUIDAndHost: (String?, String?) {
        get {
            let components = self.components(separatedBy: ":")
            if components.count > 1 {
                let uuid = components[1]
                let host = (components.count > 2) ? components[2] : nil
                
                return (uuid, host)
            }
            return (nil, nil)
        }
    }
    
    var isValidEmail: Bool {
        get {
            let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
            return emailPred.evaluate(with: self)
        }
    }
    
    var isValidHTML: Bool {
        if self.isEmpty {
            return false
        }
        return (self.range(of: "<(\"[^\"]*\"|'[^']*'|[^'\">])*>", options: .regularExpression) != nil)
    }
    
    var abbreviatedLink : String {
        if self.length > 30 {
            let first25 = String(self.prefix(20))
            let last5 = String(self.suffix(5))
            
            return "\(first25)...\(last5)"
        }
        return self
    }
    
    func decodeJWT() -> (header: [String: Any]?, payload: [String: Any]?, signature: String?) {
        let segments = self.split(separator: ".").map(String.init)
        guard segments.count == 3 else {
            print("Invalid JWT structure")
            return (nil, nil, nil)
        }

        let header = decodeBase64Url(segments[0])
        let payload = decodeBase64Url(segments[1])
        let signature = segments[2] // Signature is not decoded, it's typically used for verification.

        return (header, payload, signature)
    }
    
    func decodeBase64Url(_ base64Url: String) -> [String: Any]? {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if necessary
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64) else {
            print("Failed to decode Base64Url string")
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json as? [String: Any]
        } catch {
            print("Failed to parse JSON: \(error)")
            return nil
        }
    }
    
    func getNameStyleString(
        lineBreak:  Bool = true
    ) -> String {
        if self == "" {
            return "-"
        }
        
        let names = self.split(separator: " ")
        var namesString = ""
        var namesCount = 0
        
        for name in names {
            if namesCount == 0 {
                namesString = "\(name)"
                namesCount += 1
            } else if namesCount == 1 {
                if lineBreak {
                    namesString = "\(namesString)\n\(name)"
                } else {
                    namesString = "\(namesString) \(name)"
                }
                namesCount += 1
            } else {
                namesString = "\(namesString) \(name)"
            }
        }
        
        return namesString
    }
    
    func getFirstNameStyleString() -> String {
        let names = self.split(separator: " ")
        if names.count > 0 {
            return String(names[0])
        }
        return "Unknown"
    }
    
    func getInitialsFromName() -> String{
        let names = self.trim().components(separatedBy: " ")
        if names.count > 1 {
            if names[0].length > 0 && names[1].length > 0 {
                return String(names[0].trim().charAt(index: 0)) + String(names[1].trim().charAt(index: 0)).uppercased()
            }
        }
        if names.count > 0 {
            if names[0].length > 0 {
                return String(names[0].trim().charAt(index: 0)).uppercased()
            }
        }
        return ""
    }
    
    func removeDuplicatedProtocol() -> String {
        let urlWithoutHTTPProtocol = self.replacingOccurrences(of: "http://", with: "")
        if urlWithoutHTTPProtocol.contains("http") {
            return urlWithoutHTTPProtocol
        }
        let urlWithoutHTTPSProtocol = self.replacingOccurrences(of: "https://", with: "")
        if urlWithoutHTTPSProtocol.contains("http") {
            return urlWithoutHTTPSProtocol
        }
        return self
    }
    
    func withDefaultValue(_ defaultValue:String) -> String {
        if self.isEmpty {
            return defaultValue
        }
        return self
    }
    
    func withURLParam(key: String, value: String) -> String {
        if self.contains("?") {
            return "\(self)&\(key)=\(value)"
        } else {
            return "\(self)?\(key)=\(value)"
        }
    }
    
    public static func getAttributedText(string: String,
                                         boldStrings: [String],
                                         font: NSFont,
                                         boldFont: NSFont,
                                         color: NSColor = NSColor.white) -> NSAttributedString {
        
        let style = NSMutableParagraphStyle()
        style.alignment = NSTextAlignment.center
        
        let normalFont = font
        let stringRange = (string as NSString).range(of: string)
        let attributedString = NSMutableAttributedString(string: string)
        attributedString.addAttribute(.foregroundColor, value: color, range: stringRange)
        attributedString.addAttribute(.font, value: normalFont, range: stringRange)
        attributedString.addAttribute(.paragraphStyle, value: style, range: stringRange)
        
        for boldString in boldStrings {
            let boldRange = (string as NSString).range(of: boldString)
            attributedString.addAttribute(.font, value: boldFont, range: boldRange)
        }
        
        return attributedString
    }
    
    func mimeType() -> String {
        let url = NSURL(fileURLWithPath: self)
        let pathExtension = url.pathExtension

        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension! as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
    
    func fileExtension() -> String {
        let components = self.components(separatedBy: ".")
        if let fileExtension = components.last {
            return fileExtension
        }
        return "txt"
    }
    
    var isSingleEmoji: Bool { count == 1 && containsEmoji }

    var containsEmoji: Bool { contains { $0.isEmoji } }

    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }

    var emojiString: String { emojis.map { String($0) }.reduce("", +) }

    var emojis: [Character] { filter { $0.isEmoji } }

    var emojiScalars: [UnicodeScalar] { filter { $0.isEmoji }.flatMap { $0.unicodeScalars } }
    
    func getLinkAction() -> String? {
        let components = self.components(separatedBy: "&")
        
        for component in components {
            if component.contains("action") {
                let elements = component.components(separatedBy: "=")
                if elements.count > 1 {
                    return elements[1]
                }
            }
        }
        return nil
    }
    
    func getLinkValueFor(key: String) -> String? {
        for component in self.components(separatedBy: "&") {
            let elements = component.components(separatedBy: "=")
            if elements.count > 1 {
                let itemKey = elements[0]
                
                if itemKey == key {
                    return component.replacingOccurrences(of: "\(itemKey)=", with: "")
                }
            }
        }
        return nil
    }
    
    func getLinkComponentWith(key: String) -> String? {
        let components = self.components(separatedBy: "&")
        
        if components.count > 0 {
            for component in components {
                let elements = component.components(separatedBy: "=")
                if elements.count > 1 {
                    let componentKey = elements[0]
                    let value = component.replacingOccurrences(of: "\(componentKey)=", with: "")
                    
                    switch(componentKey) {
                    case key:
                        return value
                    default:
                        break
                    }
                }
            }
        }
        
        return nil
    }
    
    func getHostAndPort(
        defaultPort: UInt16
    ) -> (String, UInt16, Bool) {
        
        var port: UInt16 = defaultPort
        
        if let portIndex = self.lastIndex(of: ":") {
            let portString = String(self[portIndex...]).replacingOccurrences(of: ":", with: "")
            
            if let portInt = UInt16(portString) {
                port = portInt
            }
        }
        
        let actualHost = self.replacingOccurrences(of: ":\(port)", with: "")
        let ssl = port == 8883
        
        return (actualHost, port, ssl)
    }
    
    func byteSize() -> Int {
        let length = self.lengthOfBytes(using: .utf8) + 360//add offset
        return length
    }
    
    var pingComponents: (String, String, String?)? {
        get {
            let components = self.components(separatedBy: ":")
            if components.count > 1 {
                let paymentHash = components[0]
                let timestamp = components[1]
                
                if components.count > 2 {
                    let tag = components[2]
                    return (paymentHash, timestamp, tag)
                }
                return (paymentHash, timestamp, nil)
            }
            return nil
        }
    }
    
    var isBase64Encoded: Bool {
        get {
            if self.count % 4 != 0 {
                return false
            }
            
            if let _ = Data(base64Encoded: self) {
                return true
            } else {
                return false
            }
        }
    }
    
    func toSeconds() -> Int {
        let elements = self.split(separator: ":")
        if (elements.count == 3) {
            let hours = Int(elements[0]) ?? 0
            let minutes = Int(elements[1]) ?? 0
            let seconds = Int(elements[2]) ?? 0
            return (seconds) + (minutes * 60) + (hours * 60 * 60)
        }
        return 0
    }
}

extension Character {
    var isSimpleEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }

    var isCombinedIntoEmoji: Bool { unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false }
    var isEmoji: Bool { isSimpleEmoji || isCombinedIntoEmoji }
}

extension StringProtocol {
    func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.lowerBound
    }
    func endIndex<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.upperBound
    }
    func indices<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Index] {
        var indices: [Index] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                indices.append(range.lowerBound)
                startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                    index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return indices
    }
    func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                result.append(range)
                startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                    index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}

extension String {
    
    var attributedStringFromHTML: NSAttributedString? {
        guard let data = data(using: .utf8) else {
            return nil
        }
        
        do {
            return try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding:String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            )
        } catch {
            return nil
        }
    }
    
    var nonHtmlRawString: String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
    
    func removingPunctuation() -> String {
        var filteredString = self
        while true {
            if let forbiddenCharRange = filteredString.rangeOfCharacter(from: CharacterSet.punctuationCharacters)  {
                filteredString.removeSubrange(forbiddenCharRange)
            } else {
                break
            }
        }
        return filteredString
    }
    
    var personHost: String? {
        let elements = self.split(separator: "/")
        if let last = elements.last {
            return self.replacingOccurrences(of: "/\(String(last))", with: "")
        }
        return nil
    }
    
    var personUUID: String? {
        let elements = self.split(separator: "/")
        if let last = elements.last {
            return String(last)
        }
        return nil
    }
    
    var tribeMemberProfileValue : String {
        if self.trim().isEmpty {
            return "-"
        }
        return self
    }
    
    var isEmptyPinnedMessage : Bool {
        return self.isEmpty || self == "_"
    }
    
    var isNotEmpty: Bool {
        return !isEmpty
    }
    
    func isNotEmptyString(with placeHolder: String) -> Bool {
        return !isEmpty && self != placeHolder
    }
    
    func substring(range: NSRange) -> String {
        let botIndex = self.index(self.startIndex, offsetBy: range.location)
        let newRange = botIndex..<self.index(botIndex, offsetBy: range.length)
        return String(self[newRange])
   }
    
    func parseContactInfoString() -> (String, String, String)? {
        let components = self.split(separator: "_").map({ String($0) })
        return (components.count >= 3) ? (components[0], components[1], components[2]) : nil
    }
    
    func toMessageInnerContent() -> MessageInnerContent? {
        return MessageInnerContent(JSONString: self)
    }
}


