//
//  S3UploaderManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 11/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import AWSS3

class S3UploaderManager {
    
    class var sharedInstance : S3UploaderManager {
        struct Static {
            static let instance = S3UploaderManager()
        }
        return Static.instance
    }
    
    func testLocalS3Connection() async {
        do {
            let uploader = try await S3Uploader(
                region: "us-east-1",
                bucketName: "stakwork-uploads-dev",
                accessKey: "test",
                secretKey: "test"
            )
            
            // Try to list files (will work even if bucket is empty)
            let files = try await uploader.listFiles()
            print("✅ Connected to local S3!")
            print("Files in bucket: \(files.count)")
            
        } catch {
            print("❌ Connection failed: \(error)")
        }
    }
    
    func uploadFileToS3(fileURL: URL) async -> String? {
        var resultURL: String? = nil
        
        do {
            // Initialize S3 uploader
            let uploader = try await S3Uploader(
                region: "us-east-1",
                bucketName: "stakwork-uploads-dev",
                accessKey: "test",
                secretKey: "test"
            )
            
            // Generate unique key for S3
            let fileName = fileURL.lastPathComponent
            let key = "uploads/\(UUID().uuidString)-\(fileName)"
            
            // Check file size to decide upload method
            let fileSize = try fileURL.fileSize()
            
            if fileSize > 5 * 1024 * 1024 { // If file is larger than 5MB
                resultURL = try await uploader.uploadLargeFile(
                    fileURL: fileURL,
                    key: key
                ) { progress in
                    print("Upload progress: \(Int(progress * 100))%")
                }
            } else {
                resultURL = try await uploader.uploadFile(
                    fileURL: fileURL,
                    key: key
                )
            }
        } catch {
            print("❌ Upload failed: \(error.localizedDescription)")
        }
        
        return resultURL
    }
}
