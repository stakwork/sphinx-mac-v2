//
//  WorkspaceTasksCollectionViewItem.swift
//  Sphinx
//
//  Created on 2025-02-25.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

class WorkspaceTasksCollectionViewItem: NSCollectionViewItem {

    static let reuseID = "WorkspaceTasksCollectionViewItem"
    static var nib: NSNib? { NSNib(nibNamed: "WorkspaceTasksCollectionViewItem", bundle: nil) }

    @IBOutlet weak var containerView: NSBox!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var statusPillBox: NSBox!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var priorityPillBox: NSBox!
    @IBOutlet weak var priorityLabel: NSTextField!
    @IBOutlet weak var repositoryLabel: NSTextField!
    @IBOutlet weak var updatedAtLabel: NSTextField!
    @IBOutlet weak var separatorView: NSBox!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        containerView.fillColor = NSColor.Sphinx.HeaderBG
        titleLabel.textColor = NSColor.Sphinx.Text
        titleLabel.font = NSFont(name: "Roboto-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        repositoryLabel.textColor = NSColor.Sphinx.SecondaryText
        repositoryLabel.font = NSFont(name: "Roboto-Regular", size: 12) ?? .systemFont(ofSize: 12)
        updatedAtLabel.textColor = NSColor.Sphinx.SecondaryText
        updatedAtLabel.font = NSFont(name: "Roboto-Regular", size: 12) ?? .systemFont(ofSize: 12)
        separatorView.fillColor = NSColor.Sphinx.Divider
        [statusPillBox, priorityPillBox].forEach {
            $0?.cornerRadius = 10
            $0?.borderType = .noBorder
        }
        [statusLabel, priorityLabel].forEach {
            $0?.textColor = .white
            $0?.font = NSFont(name: "Roboto-Medium", size: 11) ?? .systemFont(ofSize: 11, weight: .medium)
        }
    }

    func render(with task: WorkspaceTask) {
        titleLabel.stringValue = task.title
        statusLabel.stringValue = task.status.replacingOccurrences(of: "_", with: " ").capitalized
        statusPillBox.fillColor = colorForStatus(task.status)
        priorityLabel.stringValue = task.priority.capitalized
        priorityPillBox.fillColor = colorForPriority(task.priority)
        repositoryLabel.stringValue = task.repositoryName ?? ""
        updatedAtLabel.stringValue = formattedDate(task.updatedAt)
    }

    private func colorForStatus(_ status: String) -> NSColor {
        switch status {
        case "DONE":        return NSColor.Sphinx.PrimaryGreen
        case "IN_PROGRESS": return NSColor.Sphinx.PrimaryBlue
        case "BLOCKED":     return NSColor.Sphinx.PrimaryRed
        default:            return .systemGray
        }
    }

    private func colorForPriority(_ priority: String) -> NSColor {
        switch priority {
        case "CRITICAL": return NSColor.Sphinx.PrimaryRed
        case "HIGH":     return NSColor.Sphinx.SphinxOrange
        case "MEDIUM":   return NSColor.Sphinx.PrimaryBlue
        default:         return .systemGray
        }
    }

    private func formattedDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }
        let display = DateFormatter()
        display.dateFormat = "MMM dd, yyyy"
        return display.string(from: date)
    }
}
