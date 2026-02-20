//
//  ContentItemsManager.swift
//  sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//
import CoreData

class ContentItemsManager {
    static let shared = ContentItemsManager()
    
    let context = CoreDataManager.sharedManager.persistentContainer.viewContext
    
    private var processingTimer: Timer?
    private var isProcessing = false
    private let processingInterval: TimeInterval = 1800
    private let maxRetries = 3
    
    private init() {}
    
    func startBackgroundProcessing(completion: (() -> ())? = nil) {
        print("🟢 Starting background processing service")
        
        processContentItems(completion: completion)
        
        processingTimer = Timer.scheduledTimer(
            withTimeInterval: processingInterval,
            repeats: true
        ) { [weak self] _ in
            self?.processContentItems()
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
    
    private func performProcessing() async {
        print("🔄 [\(Date())] Starting processing cycle")
        
        let startTime = Date()
        
        let uploadedCount = await processUploadedAndFailedItems()
        
        let checkedCount = await checkProcessingItems()
        
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ Processing complete in \(String(format: "%.2f", duration))s")
        print("   - Uploaded items processed: \(uploadedCount)")
        print("   - Processing items checked: \(checkedCount)")
    }
    
    private func processUploadedAndFailedItems() async -> Int {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
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
    
    private func checkProcessingItems() async -> Int {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
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
    
    private func processItemWithRetry(_ item: ContentItem, context: NSManagedObjectContext) async -> Bool {
        for attempt in 1...maxRetries {
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
                    response = try await API.sharedInstance.checkItemNodeExists(url: item.value)
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
                
            } catch {
                print("✗ Attempt \(attempt) failed for item \(item.uuid?.uuidString ?? "Empty UUID"): \(error)")
                
                if attempt == maxRetries {
                    await context.performSafely {
                        item.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                        item.errorMessage = "Failed after \(self.maxRetries) attempts: \(error.localizedDescription)"
                    }
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        
        return false
    }
    
    private func checkItemWithRetry(_ item: ContentItem, context: NSManagedObjectContext) async -> Bool {
        for attempt in 1...maxRetries {
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
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        
        return false
    }
    
    func add(value: String) {
        let context = CoreDataManager.sharedManager.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
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
            Task {
                if contentitem.shouldBeUploaded() {
                    if let resultUrl = await S3UploaderManager.sharedInstance.uploadFileToS3(fileURL: url) {
                        await context.performSafely {
                            contentitem.value = resultUrl
                            contentitem.status = Int16(ContentItem.ContentItemStatus.uploaded.rawValue)
                        }
                        
                        let _ = await self.processItemWithRetry(contentitem, context: context)
                    } else {
                        await context.performSafely {
                            contentitem.status = Int16(ContentItem.ContentItemStatus.error.rawValue)
                        }
                    }
                } else {
                    let _ = await self.processItemWithRetry(contentitem, context: context)
                }
                
                await context.performSafely {
                    context.saveContext()
                }
            }
        }
    }
    
    func addMultiple(_ values: [String]) {
        for value in values {
            add(value: value)
        }
    }
    
    func createTextFile(content: String, fileName: String) -> URL? {
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
