//
//  S3Uploader.swift
//  sphinx
//
//  Created by Tomas Timinskas on 11/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import Foundation
import AWSS3
import ClientRuntime
import AWSClientRuntime
import SmithyIdentity
import Smithy
import SmithyHTTPAPI
import UniformTypeIdentifiers

class S3Uploader {
    private let bucketName: String
    private let localEndpoint: String?
    private var awsClient: S3Client?
    private let accessKey: String?
    private let secretKey: String?
    private let region: String
    
    init(
        region: String = "us-east-1",
        bucketName: String,
        accessKey: String? = nil,
        secretKey: String? = nil,
        endpoint: String? = nil
    ) async throws {
        
        guard !bucketName.isEmpty else {
            throw S3Error.invalidConfiguration("Bucket name cannot be empty")
        }
        
        self.bucketName = bucketName
        self.localEndpoint = endpoint ?? UserData.sharedInstance.getPersonalGraphAPIUrl()
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        
        // Only initialize AWS client if not using local endpoint
        if endpoint == nil {
            var config: S3Client.S3ClientConfiguration
            
            if let accessKey = accessKey, let secretKey = secretKey {
                let credentials = AWSCredentialIdentity(
                    accessKey: accessKey,
                    secret: secretKey
                )
                
                let identityResolver = StaticAWSCredentialIdentityResolver(credentials)
                
                config = try await S3Client.S3ClientConfiguration(
                    awsCredentialIdentityResolver: identityResolver,
                    region: region
                )
            } else {
                config = try await S3Client.S3ClientConfiguration(
                    region: region
                )
            }
            
            self.awsClient = S3Client(config: config)
        }
    }
    
    func uploadFile(
        fileURL: URL,
        key: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw S3Error.fileNotFound(fileURL.path)
        }
        
        guard !key.isEmpty else {
            throw S3Error.invalidConfiguration("S3 key cannot be empty")
        }
        
        // Use direct HTTP for local endpoint
        if let endpoint = localEndpoint {
            return try await uploadViaHTTP(
                endpoint: endpoint,
                fileURL: fileURL,
                key: key
            )
        }
        
        // Use AWS SDK for production
        guard let client = awsClient else {
            throw S3Error.invalidConfiguration("AWS client not initialized")
        }
        
        let data = try Data(contentsOf: fileURL)
        let contentType = fileURL.mimeType()
        let body: ByteStream = .data(data)
        
        let putObjectInput = PutObjectInput(
            body: body,
            bucket: bucketName,
            contentType: contentType,
            key: key
        )
        
        _ = try await client.putObject(input: putObjectInput)
        
        return "https://\(bucketName).s3.amazonaws.com/\(key)"
    }
    
    private func uploadViaHTTP(
        endpoint: String,
        fileURL: URL,
        key: String
    ) async throws -> String {
        
        let data = try Data(contentsOf: fileURL)
        let contentType = fileURL.mimeType()
        
        // Build URL: http://localhost:4566/bucket-name/key
        let urlString = "\(endpoint)/\(bucketName)/\(key)"
        
        guard let url = URL(string: urlString) else {
            throw S3Error.invalidConfiguration("Invalid URL: \(urlString)")
        }
        
        print("📤 Uploading to: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error.uploadFailed("Invalid response")
        }
        
        print("📥 Response status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: responseData, encoding: .utf8) ?? "No body"
            print("❌ Error body: \(body)")
            throw S3Error.uploadFailed("Status \(httpResponse.statusCode): \(body)")
        }
        
        print("✅ Upload successful")
        return urlString
    }
    
    func uploadLargeFile(
        fileURL: URL,
        key: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> String {
        
        // For local, just use regular upload
        if localEndpoint != nil {
            return try await uploadFile(fileURL: fileURL, key: key)
        }
        
        // AWS multipart upload implementation
        guard let client = awsClient else {
            throw S3Error.invalidConfiguration("AWS client not initialized")
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw S3Error.fileNotFound(fileURL.path)
        }
        
        let fileSize = try fileURL.fileSize()
        let partSize = 5 * 1024 * 1024
        
        let createInput = CreateMultipartUploadInput(
            bucket: bucketName,
            contentType: fileURL.mimeType(),
            key: key
        )
        let createResponse = try await client.createMultipartUpload(input: createInput)
        
        guard let uploadId = createResponse.uploadId else {
            throw S3Error.invalidUploadId
        }
        
        var completedParts: [S3ClientTypes.CompletedPart] = []
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        var partNumber = 1
        var uploadedBytes: Int64 = 0
        
        while uploadedBytes < fileSize {
            let data = fileHandle.readData(ofLength: partSize)
            if data.isEmpty { break }
            
            let body: ByteStream = .data(data)
            
            let uploadPartInput = UploadPartInput(
                body: body,
                bucket: bucketName,
                key: key,
                partNumber: partNumber,
                uploadId: uploadId
            )
            
            let uploadPartResponse = try await client.uploadPart(input: uploadPartInput)
            
            completedParts.append(S3ClientTypes.CompletedPart(
                eTag: uploadPartResponse.eTag,
                partNumber: partNumber
            ))
            
            uploadedBytes += Int64(data.count)
            partNumber += 1
            
            await MainActor.run {
                progressHandler?(Double(uploadedBytes) / Double(fileSize))
            }
        }
        
        let completedUpload = S3ClientTypes.CompletedMultipartUpload(parts: completedParts)
        let completeInput = CompleteMultipartUploadInput(
            bucket: bucketName,
            key: key,
            multipartUpload: completedUpload,
            uploadId: uploadId
        )
        
        _ = try await client.completeMultipartUpload(input: completeInput)
        
        return "https://\(bucketName).s3.amazonaws.com/\(key)"
    }
    
    func listFiles(prefix: String? = nil, maxKeys: Int = 1000) async throws -> [String] {
        
        // For local endpoint, use HTTP
        if let endpoint = localEndpoint {
            return try await listFilesViaHTTP(endpoint: endpoint, prefix: prefix, maxKeys: maxKeys)
        }
        
        // For AWS, use SDK
        guard let client = awsClient else {
            throw S3Error.invalidConfiguration("AWS client not initialized")
        }
        
        let listInput = ListObjectsV2Input(
            bucket: bucketName,
            maxKeys: maxKeys,
            prefix: prefix
        )
        
        let response = try await client.listObjectsV2(input: listInput)
        return response.contents?.compactMap { $0.key } ?? []
    }
    
    private func listFilesViaHTTP(endpoint: String, prefix: String?, maxKeys: Int) async throws -> [String] {
        var urlString = "\(endpoint)/\(bucketName)/?list-type=2&max-keys=\(maxKeys)"
        if let prefix = prefix {
            urlString += "&prefix=\(prefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prefix)"
        }
        
        print("📋 Listing files: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            throw S3Error.invalidConfiguration("Invalid URL: \(urlString)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw S3Error.uploadFailed("Invalid response")
        }
        
        print("📥 List response status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            print("❌ Error body: \(body)")
            throw S3Error.uploadFailed("List failed with status \(httpResponse.statusCode)")
        }
        
        // Parse XML response
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        return parseS3ListResponse(xmlString)
    }
    
    private func parseS3ListResponse(_ xml: String) -> [String] {
        var keys: [String] = []
        let pattern = "<Key>(.*?)</Key>"
        
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let range = Range(match.range(at: 1), in: xml) {
                    keys.append(String(xml[range]))
                }
            }
        }
        
        return keys
    }
    
    func deleteFile(key: String) async throws {
        guard !key.isEmpty else {
            throw S3Error.invalidConfiguration("S3 key cannot be empty")
        }
        
        if let endpoint = localEndpoint {
            let urlString = "\(endpoint)/\(bucketName)/\(key)"
            
            print("🗑️ Deleting: \(urlString)")
            
            guard let url = URL(string: urlString) else {
                throw S3Error.invalidConfiguration("Invalid URL")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw S3Error.uploadFailed("Invalid response")
            }
            
            print("📥 Delete response status: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: responseData, encoding: .utf8) ?? "No body"
                throw S3Error.uploadFailed("Delete failed with status \(httpResponse.statusCode): \(body)")
            }
            
            print("✅ Delete successful")
            return
        }
        
        guard let client = awsClient else {
            throw S3Error.invalidConfiguration("AWS client not initialized")
        }
        
        let deleteInput = DeleteObjectInput(bucket: bucketName, key: key)
        _ = try await client.deleteObject(input: deleteInput)
    }
}

enum S3Error: Error, LocalizedError {
    case invalidUploadId
    case uploadFailed(String)
    case invalidData
    case invalidConfiguration(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidUploadId:
            return "Invalid upload ID"
        case .uploadFailed(let msg):
            return "Upload failed: \(msg)"
        case .invalidData:
            return "Invalid data"
        case .invalidConfiguration(let msg):
            return "Configuration error: \(msg)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

extension URL {
    func mimeType() -> String {
        if let typeID = try? self.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
           let utType = UTType(typeID),
           let mimeType = utType.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }
    
    func fileSize() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: self.path)
        guard let size = attributes[.size] as? Int64 else {
            throw S3Error.invalidData
        }
        return size
    }
}
