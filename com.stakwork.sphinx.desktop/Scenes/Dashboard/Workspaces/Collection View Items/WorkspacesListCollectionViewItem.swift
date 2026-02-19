//
//  WorkspacesListCollectionViewItem.swift
//  Sphinx
//
//  Created on 2025-02-19.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

class WorkspacesListCollectionViewItem: NSCollectionViewItem {

    static let reuseID = "WorkspacesListCollectionViewItem"

    static var nib: NSNib? {
        return NSNib(nibNamed: "WorkspacesListCollectionViewItem", bundle: nil)
    }

    @IBOutlet weak var containerView: NSBox!
    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var roleLabel: NSTextField!
    @IBOutlet weak var membersLabel: NSTextField!
    @IBOutlet weak var separatorView: NSBox!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        containerView.fillColor = NSColor.Sphinx.HeaderBG

        nameLabel.textColor = NSColor.Sphinx.Text
        nameLabel.font = NSFont(name: "Roboto-Medium", size: 14) ?? NSFont.systemFont(ofSize: 14, weight: .medium)

        roleLabel.textColor = NSColor.Sphinx.SecondaryText
        roleLabel.font = NSFont(name: "Roboto-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .regular)

        membersLabel.textColor = NSColor.Sphinx.SecondaryText
        membersLabel.font = NSFont(name: "Roboto-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .regular)

        separatorView.fillColor = NSColor.Sphinx.Divider
    }

    func render(with item: WorkspacesListViewController.DataSourceItem) {
        nameLabel.stringValue = item.name
        roleLabel.stringValue = item.role
        membersLabel.stringValue = "Members: \(item.memberCount)"
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    private func updateSelectionAppearance() {
        if isSelected {
            containerView.fillColor = NSColor.Sphinx.HeaderBG.withAlphaComponent(0.7)
        } else {
            containerView.fillColor = NSColor.Sphinx.HeaderBG
        }
    }
}
