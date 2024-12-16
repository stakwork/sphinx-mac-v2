//
//  AddAttachmentCollectionViewItem.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 13/12/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol AddAttachmentDelegate: AnyObject {
    func didClickAddAttachment()
}

class AddAttachmentCollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var backgroundBox: NSBox!
    @IBOutlet weak var addButton: CustomButton!
    
    weak var delegate: AddAttachmentDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        backgroundBox.wantsLayer = true
        
        if let layer = backgroundBox.layer {
            layer.backgroundColor = NSColor.Sphinx.MainBottomIcons.withAlphaComponent(0.15).cgColor
            layer.cornerRadius = 10
        }
        
        addButton.cursor = .pointingHand
    }
    
    func configureWith(delegate: AddAttachmentDelegate) {
        self.delegate = delegate
    }
    
    @IBAction func addButtonClicked(_ sender: Any) {
        delegate?.didClickAddAttachment()
    }
}
