//
//  FileAnalizer.swift
//  sphinx
//
//  Created by Tomas Timinskas on 03/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import UniformTypeIdentifiers
import AppKit

enum FileAnalysisResult {
    case localImageFile(URL)
    case localVideoFile(URL)
    case localFile(URL, UTType?)
    case urlString(URL)
    case plainText(String)
    
    var isLocalImage: Bool {
        if case .localImageFile = self { return true }
        return false
    }
    
    var isLocalVideo: Bool {
        if case .localVideoFile = self { return true }
        return false
    }
    
    var isLocalMedia: Bool {
        return isLocalImage || isLocalVideo
    }
}

class FileAnalyzer {
    
    static func analyze(_ string: String) -> FileAnalysisResult {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let url: URL?
        
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file://") {
            if trimmed.hasPrefix("file://") {
                url = URL(string: trimmed)
            } else {
                let expandedPath = NSString(string: trimmed).expandingTildeInPath
                url = URL(fileURLWithPath: expandedPath)
            }
        } else if let testURL = URL(string: trimmed), testURL.scheme != nil {
            url = testURL
        } else {
            return .plainText(trimmed)
        }
        
        guard let url = url else {
            return .plainText(trimmed)
        }
        
        if url.isFileURL || url.scheme == nil {
            let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return .plainText(trimmed)
            }
            
            if isVideoFile(fileURL) {
                return .localVideoFile(fileURL)
            }
            
            if isImageFile(fileURL) {
                return .localImageFile(fileURL)
            }
            
            let fileType = getFileType(fileURL)
            return .localFile(fileURL, fileType)
        }
        
        return .urlString(url)
    }
    
    // MARK: - Image Detection
    
    static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico", "svg"]
        let ext = url.pathExtension.lowercased()
        
        if imageExtensions.contains(ext) {
            return true
        }
        
        if let utType = getFileType(url) {
            return utType.conforms(to: .image)
        }
        
        return false
    }
    
    // MARK: - Video Detection
    
    static func isVideoFile(_ url: URL) -> Bool {
        let videoExtensions = [
            "mp4", "m4v", "mov", "avi", "mkv", "flv", "wmv", "webm",
            "mpeg", "mpg", "3gp", "ogv", "m2ts", "mts", "ts"
        ]
        let ext = url.pathExtension.lowercased()
        
        if videoExtensions.contains(ext) {
            return true
        }
        
        if let utType = getFileType(url) {
            return utType.conforms(to: .movie) || utType.conforms(to: .video)
        }
        
        return false
    }
    
    static func getFileType(_ url: URL) -> UTType? {
        if let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
           let typeIdentifier = resourceValues.typeIdentifier,
           let utType = UTType(typeIdentifier) {
            return utType
        }
        
        return UTType(filenameExtension: url.pathExtension)
    }
    
    // MARK: - Convenience Methods
    
    static func isLocalImagePath(_ string: String) -> Bool {
        if case .localImageFile = analyze(string) {
            return true
        }
        return false
    }
    
    static func isLocalVideoPath(_ string: String) -> Bool {
        if case .localVideoFile = analyze(string) {
            return true
        }
        return false
    }
    
    static func isLocalMediaPath(_ string: String) -> Bool {
        let result = analyze(string)
        return result.isLocalMedia
    }
}
