//
//  ClipboardHelper.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 02/06/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

class ClipboardHelper {
    
    public static func copyToClipboard(text: String, message: String? = "text.copied.clipboard".localized, bubbleContainer: NSView? = nil) {
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(text, forType: .string)
        
        if let message = message {
            NewMessageBubbleHelper().showGenericMessageView(text: message, in: bubbleContainer)
        }
    }
    
    public static func addImageToClipboard(image:NSImage,bubbleContainer: NSView? = nil){
        if let cgImage = image.cgImage{
            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            let jpegData = bitmapRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [:])!
            pasteBoard.setData(jpegData, forType: .png)
            
            let message = "Copied image to the clipboard"
            NewMessageBubbleHelper().showGenericMessageView(text: message, in: bubbleContainer)
        }
    }
    
    public static func addVcImageToClipboard(
        screenshot: NSImage,
        bubbleContainer: NSView? = nil
    ) {
        
        /*
        var displayCount: UInt32 = 0;
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        if (result != CGError.success) {
            print("error: \(result)")
            return
        }
        let allocated = Int(displayCount)
        let activeDisplays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: allocated)
        result = CGGetActiveDisplayList(displayCount, activeDisplays, &displayCount)
        
        if (result != CGError.success) {
            print("error: \(result)")
            return
        }
           
        for i in 1...displayCount {
            let screenShot:CGImage = CGDisplayCreateImage(activeDisplays[Int(i-1)])!
            let bitmapRep = NSBitmapImageRep(cgImage: screenShot)
            let jpegData = bitmapRep.representation(using: NSBitmapImageRep.FileType.jpeg, properties: [:])!
            
            
            NSPasteboard.general.setData(jpegData, forType: .png)
        }
         */
        
        //if let screenshot : NSImage = vc.view.bitmapImage(),
        if let _ :CGImage = screenshot.cgImage {
//            let bitmapRep = NSBitmapImageRep(cgImage: cgScreenshot)
            let data = screenshot.sd_imageData()
            NSPasteboard.general.setData(data, forType: .png)
            
            NewMessageBubbleHelper().showGenericMessageView(text: "QR Code Copied to Clipboard", in: bubbleContainer)
        }
        
    }

    func CreateTimeStamp() -> Int32
    {
        return Int32(Date().timeIntervalSince1970)
    }
    
    func clipboardHasFiles(pasteBoard: NSPasteboard) -> Bool {
        if let files = pasteBoard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], files.count > 0 {
            let fileUrls = files.filter({ $0.isFileURL })
            return fileUrls.count > 0
        } else if let images = pasteBoard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], images.count > 0 {
            return images.count > 0
        }
        return false
    }
}


extension NSView {
    func bitmapImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        guard let cgImage = rep.cgImage else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: bounds.size)
    }
}
