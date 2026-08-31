//
//  ContentItemsManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import CoreData

@MainActor
class ContentItemsManager {
    static let shared = ContentItemsManager()
    
    let context = CoreDataManager.sharedManager.persistentContainer.viewContext
    
    private var processingTimer: Timer?
    private var isProcessing = false
    private let processingInterval: TimeInterval = 1800
    nonisolated static let maxRetries = 3
    
    private init() {}
    
    func startBackgroundProcessing(completion: (() -> ())? = nil) {
        print("🟢 Starting background processing service")
        
        processContentItems(completion: completion)
        
        processingTimer = Timer.scheduledTimer(
            withTimeInterval: processingInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.processContentItems()
            }
        }
        
        RunLoop.current.add(processingTimer!, forMode: .common)
    }
    
    func stopBackgroundProcessing() {
        print("🔴 Stopping background processing service")
        processingTimer?.invalidate()
        processingTimer = nil
    }
    
    func processContentItems(completion: (() -> ())? = nil) {
        guard !isProcessing else {
            print("⚠️ Already processing, skipping...")
            return
        }
        
        isProcessing = true
        
        Task {
            await performProcessing()
            isProcessing = false
            completion?()
        }
    }
    
    nonisolated private func performProcessing() async {
        print("🔄 [\(Date())] Starting processing cycle")
        
        let startTime = Date()
        
        let uploadedCount = await processUploadedAndFailedItems()
        
        let checkedCount = await checkProcessingItems()
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Processing complete in \(String(format: "%.2f", duration))s")
        print("   - Uploaded items processed: \(uploadedCount)")
        print("   - Processing items checked: \(checkedCount)")
    }
    
    nonisolated private func processUploadedAndFailedItems() async -> Int {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        var processedCount = 0
        
        let items = ContentItem.getContentItemsWith(
            statuses: [ContentItem.ContentItemStatus.uploaded.rawValue, ContentItem.ContentItemStatus.error.rawValue],
            filterRetriedItems: true,
            managedContext: context
        )
        
        for item in items {
            let success = await processItemWithRetry(item, context: context)
            if success {
                processedCount += 1
            }
        }
        
        context.saveContext()
        
        return processedCount
    }
    
    nonisolated private func checkProcessingItems() async -> Int {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        var checkedCount = 0
        
        let items = ContentItem.getContentItemsWith(
            status: ContentItem.ContentItemStatus.processing.rawValue,
            managedContext: context
        )
        
        for item in items {
            let success = await checkItemWithRetry(item, context: context)
            if success {
                checkedCount += 1
            }
        }
        
        context.saveContext()
        
        return checkedCount
    }
    
    nonisolated private func processItemWithRetry(_ item: ContentItem, context: NSManagedObjectContext) async -> Bool {
        ///Kept so a later "already exists" collision can report what actually went wrong
        ///on the first attempt instead of the duplicate it caused.
        var firstFailure: String? = nil

        for attempt in 1...ContentItemsManager.maxRetries {
            do {
                var response: API.CheckNodeResponse? = nil
                var didRetry = false
                
                if item.status == Int16(ContentItem.ContentItemStatus.error.rawValue) {
                    if let refId = item.referenceId, item.value.isValidURL, !didRetry {
                        response = try await API.sharedInstance.createGraphMindsetRunForItem(url: item.value, refId: refId)
                        didRetry = true
                    } else {
                        return true
                    }
                } else {
                    response = try await API.sharedInstance.checkItemNodeExists(
                        url: item.value,
                        contentType: API.graphContentType(for: item.type)
                    )
                }
                
                
                await context.performSafely {
                    item.status = Int16(ContentItem.ContentItemStatus.processing.rawValue)
                    item.lastProcessedAt = Date()
                    item.errorMessage = nil
                    item.referenceId = response?.refId
                    item.didRetry = didRetry
                    
                    if let projectId = response?.projectId {
                        item.projectId = String(projectId)
                    }
                }
                
                print("✓ Item \(item.uuid?.uuidString ?? "Empty UUID") processed (attempt \(attempt))")
                return true
                
            } catch API.NodeError.alreadyExists(let nodeKey) {
                ///Only benign on the FIRST attempt, where it means the content was
                ///genuinely ingested earlier. On a later attempt it is our own doing:
                ///the backend creates the Neo4j node before dispatching to Stakwork, so
                ///a failed attempt leaves the node behind and every retry then collides
                ///with it. Reporting that as success would hide the original failure.
                if attempt == 1 {
                    print("• Item \(item.uuid?.uuidString ?? "Empty UUID") is already in the graph (node_key: \(nodeKey ?? "unknown"))")

                    await context.performSafely {
                        item.status = Int16(ContentItem.ContentItemStatus.success.rawValue)
                        item.errorMessage = nil
                        item.lastProcessedAt = Date()
                    }
                    return true
                }

                print("✗ Item \(item.uuid?.uuidString ?? "Empty UUID") collided with the node its own attempt 1 left behind; reporting the original failure")

                await context.performSafely {
                    item.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                    item.errorMessage = firstFailure ?? "Node already exists in the graph"
                }
                return false

            } catch let error as API.NodeError {
                ///A structured {errorCode, message} rejection is a business error, not a
                ///transient one — retrying cannot change the answer, and because node
                ///creation is not idempotent it actively corrupts the diagnostic by
                ///turning attempt 2 into a misleading "already exists". Stop here.
                print("✗ processItem rejected for item \(item.uuid?.uuidString ?? "Empty UUID") (attempt \(attempt), not retrying)")
                print("   value: \(item.value)")
                print("   error: \(error)")

                await context.performSafely {
                    item.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                    item.errorMessage = error.localizedDescription
                }
                return false

            } catch {
                print("✗ processItem attempt \(attempt)/\(ContentItemsManager.maxRetries) failed for item \(item.uuid?.uuidString ?? "Empty UUID")")
                print("   value: \(item.value)")
                print("   error: \(error)")

                if firstFailure == nil {
                    firstFailure = error.localizedDescription
                }

                if attempt == ContentItemsManager.maxRetries {
                    await context.performSafely {
                        item.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                        item.errorMessage = "Failed after \(ContentItemsManager.maxRetries) attempts: \(error.localizedDescription)"
                    }
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        
        return false
    }
    
    nonisolated private func checkItemWithRetry(_ item: ContentItem, context: NSManagedObjectContext) async -> Bool {
        for attempt in 1...ContentItemsManager.maxRetries {
            guard let referenceId = item.referenceId else {
                continue
            }
            
            do {
                if let projectId = item.projectId {
                    let projectResponse = try await API.sharedInstance.checkProjectStatus(projectId: projectId)
                    
                    await context.performSafely {
                        item.status = Int16(projectResponse.completed ? ContentItem.ContentItemStatus.success.rawValue : (projectResponse.processing ? ContentItem.ContentItemStatus.processing.rawValue : ContentItem.ContentItemStatus.error.rawValue))
                        item.errorMessage = projectResponse.errorMessage
                        item.lastProcessedAt = Date()
                    }
                    
                    return true
                }
                
                let response = try await API.sharedInstance.checkItemNodeStatus(refId: referenceId)
 
                await context.performSafely {
                    item.status = Int16(response.completed ? ContentItem.ContentItemStatus.success.rawValue : (response.processing ? ContentItem.ContentItemStatus.processing.rawValue : ContentItem.ContentItemStatus.error.rawValue))
                    item.lastProcessedAt = Date()
                    
                    if response.completed {
                        item.errorMessage = nil
                    } else if !response.completed {
                        item.errorMessage = "Run failed"
                    }
                }
                
                return true
            } catch {
                print("✗ checkItem attempt \(attempt)/\(ContentItemsManager.maxRetries) failed for item \(item.uuid?.uuidString ?? "Empty UUID")")
                print("   refId: \(referenceId), projectId: \(item.projectId ?? "none")")
                print("   error: \(error)")

                if attempt < ContentItemsManager.maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }

        return false
    }
    
    ///Works entirely on a background Core Data context, so it stays off the main actor
    nonisolated func add(value: String) {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        let contentitem = ContentItem.saveObjectFrom(value: value, context: context)
        
        guard let contentitem = contentitem else {
            return
        }
        
        if contentitem.type == ContentItem.ContentType.text.rawValue {
            if let url = createTextFile(content: contentitem.value, fileName: "text.\(Date.timeIntervalSinceReferenceDate).txt") {
                context.performSafely {
                    contentitem.value = url.absoluteString
                }
            } else {
                context.performSafely {
                    contentitem.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                    context.saveContext()
                }
                return
            }
        }
        
        if let url = URL(string: contentitem.value) {
            Task { await processAddedItem(contentitem, url: url, context: context) }
        }
    }

    nonisolated private func processAddedItem(_ contentitem: ContentItem, url: URL, context: NSManagedObjectContext) async {
        if contentitem.shouldBeUploaded() {
            print("↑ Uploading dropped file to S3: \(url.path)")
            print("   S3 endpoint: \(UserData.sharedInstance.getPersonalGraphS3Url() ?? "MISSING — no personal graph url set")")

            if let resultUrl = await S3UploaderManager.sharedInstance.uploadFileToS3(fileURL: url) {
                print("↑ Upload succeeded: \(resultUrl)")

                await context.performSafely {
                    contentitem.value = resultUrl
                    contentitem.status = Int16(ContentItem.ContentItemStatus.uploaded.rawValue)
                }
                let _ = await processItemWithRetry(contentitem, context: context)
            } else {
                print("✗ Upload to S3 failed for \(url.path) — see S3Uploader logs above for the cause")

                await context.performSafely {
                    contentitem.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                    contentitem.errorMessage = "Upload to S3 failed"
                }
            }
        } else {
            let _ = await processItemWithRetry(contentitem, context: context)
        }

        await context.performSafely {
            context.saveContext()
        }
    }
    
    func addMultiple(_ values: [String]) {
        for value in values {
            add(value: value)
        }
    }
    
    nonisolated func createTextFile(content: String, fileName: String) -> URL? {
        // Get documents directory
        guard let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        
        // Create file URL
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            // Write string to file
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Load
    
    func load() -> [ContentItem] {
        return ContentItem.getAllContentItems(context: context)
    }
    
    // MARK: - Delete
    
    func remove(with value: String) {
        if let contenItem = ContentItem.getContentItemWith(value: value) {
            CoreDataManager.sharedManager.deleteObject(object: contenItem, context: context)
        }
        context.saveContext()
    }
    
    func remove(with uuid: UUID) {
        if let contenItem = ContentItem.getContentItemWith(uuid: uuid) {
            CoreDataManager.sharedManager.deleteObject(object: contenItem, context: context)
        }
        context.saveContext()
    }
    
    func removeAll() {
        for item in ContentItem.getAllContentItems(context: context) {
            CoreDataManager.sharedManager.deleteObject(object: item, context: context)
        }
        context.saveContext()
    }
    
    func getByType(_ type: ContentItem.ContentType) {
        for item in ContentItem.getContentItesmWith(type: type.rawValue, managedContext: context) {
            CoreDataManager.sharedManager.deleteObject(object: item, context: context)
        }
        context.saveContext()
    }
    
    func set(value: String, forUUID uuid: UUID) {
        if let contenItem = ContentItem.getContentItemWith(uuid: uuid) {
            contenItem.value = value
            contenItem.managedObjectContext?.saveContext()
        }
    }
}
