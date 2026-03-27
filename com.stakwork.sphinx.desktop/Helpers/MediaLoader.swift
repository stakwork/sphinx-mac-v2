//
//  MediaLoader.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 14/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import AVFoundation
import SDWebImage

@MainActor class MediaLoader {
    
    nonisolated(unsafe) static let cache = SphinxCache()
    
    nonisolated class func isAuthenticated() -> (Bool, String?) {
        if let token: String = UserDefaults.Keys.attachmentsToken.get() {
            let expDate: Date? = UserDefaults.Keys.attachmentsTokenExpDate.get()
            
            if let expDate = expDate, expDate > Date() {
                return (true, token)
            }
        }
        return (false, nil)
    }
    
    nonisolated class func loadDataFrom(URL: URL, includeToken: Bool = true, completion: @escaping @MainActor (Data, String?) -> (), errorCompletion: @escaping @MainActor () -> ()) {
        if !ConnectivityHelper.isConnectedToInternet {
            Task { @MainActor in errorCompletion() }
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 30
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        var request = URLRequest(url: URL as URL)
        
        let isAuthenticated = MediaLoader.isAuthenticated()
        
        if !isAuthenticated.0 {
            AttachmentsManager.sharedInstance.authenticate(completion: {
                self.loadDataFrom(
                    URL: URL,
                    includeToken: includeToken,
                    completion: completion,
                    errorCompletion: errorCompletion
                )
            }, errorCompletion: {
                Task { @MainActor in errorCompletion() }
            })
            return
        }
        
        if let token: String = isAuthenticated.1, includeToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpMethod = "GET"
        
        let task = session.dataTask(with: request, completionHandler: { (data: Data?, response: URLResponse?, error: Error?) -> Void in
            if let _ = error {
                Task { @MainActor in errorCompletion() }
            } else if let data = data {
                let fileName = response?.getFileName()
                Task { @MainActor in completion(data, fileName) }
            }
        })
        task.resume()
    }
    
    @MainActor class func asyncLoadImage(imageView: NSImageView, nsUrl: URL, placeHolderImage: NSImage?, completion: (() -> ())? = nil) {
        imageView.sd_setImage(with: nsUrl, placeholderImage: placeHolderImage, options: [SDWebImageOptions.progressiveLoad, SDWebImageOptions.retryFailed], completed: { (image, error, _, _) in
            if let completion = completion, let _ = image {
                DispatchQueue.main.async {
                    completion()
                }
            }
        })
    }
    
    @MainActor class func asyncLoadImage(imageView: NSImageView, nsUrl: URL, placeHolderImage: NSImage?, id: Int, completion: @escaping @MainActor (NSImage, Int) -> (), errorCompletion: ((Error) -> ())? = nil) {
        imageView.sd_setImage(with: nsUrl, placeholderImage: placeHolderImage, options: SDWebImageOptions.progressiveLoad, completed: { (image, error, _, _) in
            if let image = image {
                Task { @MainActor in
                    completion(image, id)
                }
            } else if let errorCompletion = errorCompletion, let error = error {
                DispatchQueue.main.async {
                    errorCompletion(error)
                }
            }
        })
    }

    @MainActor class func asyncLoadImage(imageView: NSImageView, nsUrl: URL, placeHolderImage: NSImage?, completion: @escaping @MainActor (NSImage) -> (), errorCompletion: ((Error) -> ())? = nil) {
        imageView.sd_setImage(with: nsUrl, placeholderImage: placeHolderImage, options: [SDWebImageOptions.progressiveLoad, SDWebImageOptions.retryFailed], completed: { (image, error, _, _) in
            if let image = image {
                Task { @MainActor in
                    completion(image)
                }
            } else if let errorCompletion = errorCompletion, let error = error {
                DispatchQueue.main.async {
                    errorCompletion(error)
                }
            }
        })
    }
    
    class func loadImage(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, NSImage) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        let isGif = message.isGif()
        
        if message.isMediaExpired() {
            clearImageCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
            return
        } else if let cachedImage = getImageFromCachedUrl(url: url.absoluteString) {
            if !isGif || (isGif && getMediaDataFromCachedUrl(url: url.absoluteString) != nil) {
                Task { @MainActor in completion(messageId, cachedImage) }
                return
            }
        }

        loadDataFrom(URL: url, completion: { data, fileName in
            message.saveFileName(fileName)
            loadImageFromData(data: data, url: url, message: message, completion: completion, errorCompletion: errorCompletion)
        }, errorCompletion: {
            Task { @MainActor in errorCompletion(messageId) }
        })
    }
    
    class func loadImageFromData(data: Data, url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, NSImage) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        let isGif = message.isGif()
        let isPdf = message.isPDF()
        var decryptedImage:NSImage? = nil
        
        if let image = NSImage(data: data) {
            decryptedImage = image
        } else if let mediaKey = message.getMediaKey(), mediaKey != "" {
            if let decryptedData = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                message.saveFileSize(decryptedData.count)
                
                if isGif || isPdf {
                    storeMediaDataInCache(data: decryptedData, url: url.absoluteString)
                }
                
                decryptedImage = getImageFromData(decryptedData, isPdf: isPdf)
            }
        }
        
        if let decryptedImage = decryptedImage {
            storeImageInCache(img: decryptedImage, url: url.absoluteString)
            Task { @MainActor in completion(messageId, decryptedImage) }
        } else {
            Task { @MainActor in errorCompletion(messageId) }
        }
    }

    nonisolated class func getImageFromData(_ data: Data, isPdf: Bool) -> NSImage? {
        if isPdf {
            if let image = data.getPDFThumbnail() {
                return image
            }
        }
        return NSImage(data: data)
    }
    
    class func loadMessageData(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, String) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        
        loadDataFrom(URL: url, completion: { data, fileName in
            if let mediaKey = message.getMediaKey(), mediaKey != "" {
                if let data = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                    let str = String(decoding: data, as: UTF8.self)
                    if str != "" {
                        Task { @MainActor in
                            message.messageContent = str
                            completion(messageId, str)
                        }
                        return
                    }
                }
            }
            Task { @MainActor in errorCompletion(messageId) }
        }, errorCompletion: {
            Task { @MainActor in errorCompletion(messageId) }
        })
    }

    class func loadVideo(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, Data, NSImage?) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        
        if message.isMediaExpired() {
            clearImageCacheFor(url: url.absoluteString)
            clearMediaDataCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
        } else if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            let image = self.getImageFromCachedUrl(url: url.absoluteString) ?? nil
            if image == nil {
                self.getThumbnailImageFromVideoData(data: data, videoUrl: url.absoluteString, completion: { image in
                    Task { @MainActor in completion(messageId, data, image) }
                })
            } else {
                Task { @MainActor in completion(messageId, data, image) }
            }
        } else {
            loadDataFrom(URL: url, completion: { data, fileName in
                message.saveFileName(fileName)
                self.loadMediaFromData(data: data, url: url, message: message, completion: { data in
                    self.getThumbnailImageFromVideoData(data: data, videoUrl: url.absoluteString, completion: { image in
                        Task { @MainActor in completion(messageId, data, image) }
                    })
                }, errorCompletion: errorCompletion)
            }, errorCompletion: {
                Task { @MainActor in errorCompletion(messageId) }
            })
        }
    }

    class func loadAudio(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, Data) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        loadFileData(url: url, message: message, completion: completion, errorCompletion: errorCompletion)
    }
    
    class func loadPDF(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, Data) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        loadFileData(url: url, message: message, completion: completion, errorCompletion: errorCompletion)
    }
    
    class func loadFileData(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, Data) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        
        if message.isMediaExpired() {
            clearMediaDataCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
        } else if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            Task { @MainActor in completion(messageId, data) }
        } else {
            loadDataFrom(URL: url, completion: { data, fileName in
                message.saveFileName(fileName)
                self.loadMediaFromData(data: data, url: url, message: message, completion: { data in
                    Task { @MainActor in completion(messageId, data) }
                }, errorCompletion: errorCompletion)
            }, errorCompletion: {
                Task { @MainActor in errorCompletion(messageId) }
            })
        }
    }

    class func getFileAttachmentData(url: URL, message: TransactionMessage, completion: @escaping @MainActor (Int, Data) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        let messageId = message.id
        
        if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            Task { @MainActor in completion(messageId, data) }
        } else {
            Task { @MainActor in errorCompletion(messageId) }
        }
    }

    class func loadMediaFromData(data: Data, url: URL, message: TransactionMessage, completion: @escaping @MainActor (Data) -> (), errorCompletion: @escaping @MainActor (Int) -> ()) {
        if let mediaKey = message.getMediaKey(), mediaKey != "" {
            if let decryptedData = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                message.saveFileSize(decryptedData.count)
                storeMediaDataInCache(data: decryptedData, url: url.absoluteString)
                Task { @MainActor in completion(decryptedData) }
                return
            }
            Task { @MainActor in errorCompletion(message.id) }
        } else {
            storeMediaDataInCache(data: data, url: url.absoluteString)
            Task { @MainActor in completion(data) }
        }
    }

    class func loadAvatarImage(url: String, objectId: Int, completion: @escaping @MainActor (NSImage?, Int) -> ()) {
        if let data = getMediaDataFromCachedUrl(url: url) {
            if let image = NSImage(data: data) {
                Task { @MainActor in completion(image, objectId) }
                return
            }
        }

        if let nsurl = URL(string: url) {
            loadDataFrom(URL: nsurl, completion: { data, _ in
                storeMediaDataInCache(data: data, url: nsurl.absoluteString)
                if let image = NSImage(data: data) {
                    Task { @MainActor in completion(image, objectId) }
                }
            }, errorCompletion: {
                Task { @MainActor in completion(nil, objectId) }
            })
        }
    }

    class func loadTemplate(row: Int, muid: String, completion: @escaping @MainActor (Int, String, NSImage) -> ()) {
        let urlString = "\(API.kAttachmentsServerUrl)/template/\(muid)"
        
        if let url = URL(string: urlString) {
            if let cachedImage = getImageFromCachedUrl(url: url.absoluteString) {
                Task { @MainActor in completion(row, muid, cachedImage) }
            } else {
                loadDataFrom(URL: url, includeToken: true, completion: { data, _ in
                    if let image = NSImage(data: data) {
                        self.storeImageInCache(img: image, url: url.absoluteString)
                        Task { @MainActor in completion(row, muid, image) }
                        return
                    }
                }, errorCompletion: {})
            }
        }
    }
    
    nonisolated class func getDataFromUrl(url: URL) -> Data? {
        var videoData: Data?
        do {
            videoData = try Data(contentsOf: url as URL, options: Data.ReadingOptions.alwaysMapped)
        } catch _ {
            videoData = nil
        }
        
        guard let data = videoData else {
            return nil
        }
        return data
    }
    
    nonisolated class func getThumbnailImageFromVideoData(data: Data, videoUrl: String?, completion: @escaping @MainActor (NSImage?) -> Void) {
        guard var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        url.appendPathComponent("video.mov")
        do {
            try data.write(to: url)
        } catch {
            return
        }
        
        let asset = AVAsset(url: url)
        
        DispatchQueue.global().async {
            let avAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            avAssetImageGenerator.appliesPreferredTrackTransform = true
            let thumnailTime = CMTimeMake(value: 5, timescale: 1)
            do {
                let cgThumbImage = try avAssetImageGenerator.copyCGImage(at: thumnailTime, actualTime: nil)
                let thumbImage = NSImage(cgImage: cgThumbImage, size: NSSize(width: 220, height: 220))
                deleteItemAt(url: url)

                if let videoUrl = videoUrl {
                    storeImageInCache(img: thumbImage, url: videoUrl)
                }
                Task { @MainActor in completion(thumbImage) }
            } catch {
                deleteItemAt(url: url)
                Task { @MainActor in completion(nil) }
            }
        }
    }
    
    nonisolated class func clearMessageMediaCache(message: TransactionMessage) {
        if let url = message.getMediaUrl() {
            clearImageCacheFor(url: url.absoluteString)
            clearMediaDataCacheFor(url: url.absoluteString)
        }
    }
    
    nonisolated class func clearImageCacheFor(url: String) {
        SDImageCache.shared.removeImage(forKey: url, withCompletion: nil)
        cache.removeValue(forKey: url)
    }
    
    nonisolated class func storeImageInCache(img: NSImage, url: String) {
        SDImageCache.shared.store(img, forKey: url, completion: nil)
    }
    
    nonisolated class func getImageFromCachedUrl(url: String) -> NSImage? {
        return SDImageCache.shared.imageFromCache(forKey: url)
    }
    
    nonisolated class func storeMediaDataInCache(data: Data, url: String) {
        cache[url] = data
    }
    
    nonisolated class func getMediaDataFromCachedUrl(url: String) -> Data? {
        return cache[url]
    }
    
    nonisolated class func clearMediaDataCacheFor(url: String) {
        return cache.removeValue(forKey: url)
    }
        
    nonisolated class func deleteItemAt(url: URL) {
        do {
            try FileManager().removeItem(at: url)
        } catch {
            
        }
    }
}

extension MediaLoader {
    nonisolated class func loadPublicImage(
        url: URL,
        messageId: Int,
        completion: @escaping @MainActor (Int, NSImage) -> (), errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        if let cachedImage = getImageFromCachedUrl(url: url.absoluteString) {
            Task { @MainActor in completion(messageId, cachedImage) }
        } else {
            loadDataFrom(URL: url, includeToken: true, completion: { (data, _) in
                if let image = NSImage(data: data) {
                    self.storeImageInCache(
                        img: image,
                        url: url.absoluteString
                    )
                    Task { @MainActor in completion(messageId, image) }
                    return
                }
            }, errorCompletion: {})
        }
    }
    
    class func loadImage(
        url: URL,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, NSImage?, Data?) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        let messageId = message.id
        let isGif = message.isGif()
        
        if message.isMediaExpired() {
            clearImageCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
            return
        } else if let cachedImage = getImageFromCachedUrl(url: url.absoluteString), !isGif {
            Task { @MainActor in completion(messageId, cachedImage, nil) }
            return
        } else if let cachedData = getMediaDataFromCachedUrl(url: url.absoluteString), isGif {
            Task { @MainActor in completion(messageId, nil, cachedData) }
            return
        }

        loadDataFrom(URL: url, completion: { (data, fileName) in
            message.saveFileName(fileName)

            loadImageFromData(
                data: data,
                url: url,
                message: message,
                mediaKey: mediaKey,
                completion: completion,
                errorCompletion: errorCompletion
            )
        }, errorCompletion: {
            Task { @MainActor in errorCompletion(messageId) }
        })
    }
    
    class func loadImageFromData(
        data: Data,
        url: URL,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, NSImage?, Data?) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        let messageId = message.id
        let isGif = message.isGif()
        let isPDF = message.isPDF()
        var decryptedImage:NSImage? = nil
        
        if let image = NSImage(data: data) {
            decryptedImage = image
        } else if let mediaKey = mediaKey, mediaKey != "" {
            if let decryptedData = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                message.saveFileSize(decryptedData.count)
                
                if isGif || isPDF {
                    storeMediaDataInCache(data: decryptedData, url: url.absoluteString)
                }
                decryptedImage = getImageFromData(decryptedData, isPdf: isPDF)
            }
        }
        
        if let decryptedImage = decryptedImage {
            storeImageInCache(
                img: decryptedImage,
                url: url.absoluteString
            )
            Task { @MainActor in completion(messageId, decryptedImage, nil) }
        } else {
            Task { @MainActor in errorCompletion(messageId) }
        }
    }

    class func loadFileData(
        url: URL,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, Data) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        let messageId = message.id
        
        if message.isMediaExpired() {
            clearMediaDataCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
        } else if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            Task { @MainActor in completion(messageId, data) }
        } else {
            loadDataFrom(URL: url, completion: { (data, fileName) in
                message.saveFileName(fileName)

                self.loadMediaFromData(
                    data: data,
                    url: url,
                    message: message,
                    mediaKey: mediaKey,
                    completion: { data in
                        Task { @MainActor in completion(messageId, data) }
                    },
                    errorCompletion: errorCompletion
                )
            }, errorCompletion: {
                Task { @MainActor in errorCompletion(messageId) }
            })
        }
    }

    class func loadFileData(
        url: URL,
        isPdf: Bool,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, Data, MessageTableCellState.FileInfo) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        let messageId = message.id
        
        if message.isMediaExpired() {
            clearMediaDataCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
        } else if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            let fileInfo = MessageTableCellState.FileInfo(
                fileSize: message.mediaFileSize,
                fileName: message.mediaFileName ?? "",
                pagesCount: isPdf ? data.getPDFPagesCount() : nil,
                previewImage: isPdf ? data.getPDFThumbnail() : nil
            )
            Task { @MainActor in completion(messageId, data, fileInfo) }
        } else {
            loadDataFrom(URL: url, completion: { (data, fileName) in
                message.saveFileName(fileName)

                self.loadMediaFromData(
                    data: data,
                    url: url,
                    message: message,
                    mediaKey: mediaKey,
                    completion: { data in
                        let fileInfo = MessageTableCellState.FileInfo(
                            fileSize: message.mediaFileSize,
                            fileName: message.mediaFileName ?? "",
                            pagesCount: isPdf ? data.getPDFPagesCount() : nil,
                            previewImage: isPdf ? data.getPDFThumbnail() : nil
                        )
                        Task { @MainActor in completion(messageId, data, fileInfo) }
                    },
                    errorCompletion: errorCompletion
                )
            }, errorCompletion: {
                Task { @MainActor in errorCompletion(messageId) }
            })
        }
    }

    class func loadMediaFromData(
        data: Data,
        url: URL, message: TransactionMessage,
        mediaKey: String? = nil,
        isVideo: Bool = false,
        completion: @escaping @MainActor (Data) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        if let mediaKey = mediaKey, mediaKey != "" {
            if let decryptedData = SymmetricEncryptionManager.sharedInstance.decryptData(
                data: data,
                key: mediaKey
            ) {
                message.saveFileSize(decryptedData.count)

                storeMediaDataInCache(
                    data: decryptedData,
                    url: url.absoluteString
                )

                Task { @MainActor in completion(decryptedData) }
                return
            }
        } else {
            storeMediaDataInCache(
                data: data,
                url: url.absoluteString
            )
            Task { @MainActor in completion(data) }
        }
    }

    class func loadVideo(
        url: URL,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, Data, NSImage?) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        let messageId = message.id
        
        if message.isMediaExpired() {
            clearImageCacheFor(url: url.absoluteString)
            clearMediaDataCacheFor(url: url.absoluteString)
            Task { @MainActor in errorCompletion(messageId) }
        } else if let data = getMediaDataFromCachedUrl(url: url.absoluteString) {
            let image = self.getImageFromCachedUrl(url: url.absoluteString) ?? nil
            if image == nil {
                self.getThumbnailImageFromVideoData(data: data, videoUrl: url.absoluteString, completion: { image in
                    Task { @MainActor in completion(messageId, data, image) }
                })
            } else {
                Task { @MainActor in completion(messageId, data, image) }
            }
        } else {
            loadDataFrom(URL: url, completion: { (data, fileName) in
                message.saveFileName(fileName)

                self.loadMediaFromData(
                    data: data,
                    url: url,
                    message: message,
                    mediaKey: mediaKey,
                    isVideo: true,
                    completion: { data in
                        self.getThumbnailImageFromVideoData(data: data, videoUrl: url.absoluteString, completion: { image in
                            Task { @MainActor in completion(messageId, data, image) }
                        })
                    },
                    errorCompletion: errorCompletion
                )
            }, errorCompletion: {
                Task { @MainActor in errorCompletion(messageId) }
            })
        }
    }

    class func loadMessageData(
        url: URL,
        message: TransactionMessage,
        mediaKey: String?,
        completion: @escaping @MainActor (Int, String) -> (),
        errorCompletion: @escaping @MainActor (Int) -> ()
    ) {
        loadDataFrom(URL: url, completion: { (data, _) in
            if let mediaKey = mediaKey, mediaKey.isNotEmpty {
                if let data = SymmetricEncryptionManager.sharedInstance.decryptData(data: data, key: mediaKey) {
                    let str = String(decoding: data, as: UTF8.self)
                    if str != "" {
                        Task { @MainActor in
                            message.messageContent = str
                            completion(message.id, str)
                        }
                        return
                    }
                }
            }
            Task { @MainActor in errorCompletion(message.id) }
        }, errorCompletion: {
            Task { @MainActor in errorCompletion(message.id) }
        })
    }
    
    class func deleteOldMedia() {
        let backgroundContext = CoreDataManager.sharedManager.getBackgroundContext()
        
        backgroundContext.performSafely {
            if let halfMonthAgo = Calendar.current.date(byAdding: .day, value: -15, to: Date()) {
                for attachment in TransactionMessage.getAttachmentsBefore(
                    date: halfMonthAgo,
                    managedContext: backgroundContext
                ) {
                    MediaLoader.clearMessageMediaCache(message: attachment)
                }
            }
        }
    }
}
