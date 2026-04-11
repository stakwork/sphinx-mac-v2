//
//  WorkspaceTasksCollectionViewItem.swift
//  Sphinx
//
//  Created on 2025-02-25.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

protocol WorkspaceTasksCollectionViewItemDelegate: AnyObject {
    func taskItem(_ item: WorkspaceTasksCollectionViewItem, didToggleRunBuild value: Bool, for taskId: String)
    func taskItem(_ item: WorkspaceTasksCollectionViewItem, didToggleRunTestSuite value: Bool, for taskId: String)
}

class WorkspaceTasksCollectionViewItem: NSCollectionViewItem {

    static let reuseID = "WorkspaceTasksCollectionViewItem"
    static var nib: NSNib? { NSNib(nibNamed: "WorkspaceTasksCollectionViewItem", bundle: nil) }

    // XIB-connected outlets
    @IBOutlet weak var containerView: NSBox!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var statusPillBox: NSBox!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var priorityPillBox: NSBox!
    @IBOutlet weak var priorityLabel: NSTextField!
    @IBOutlet weak var repositoryLabel: NSTextField!
    @IBOutlet weak var updatedAtLabel: NSTextField!
    @IBOutlet weak var separatorView: NSBox!

    // Programmatically created toggle controls
    private var runBuildSwitch: NSSwitch!
    private var runBuildLabel: NSTextField!
    private var runTestSuiteSwitch: NSSwitch!
    private var runTestSuiteLabel: NSTextField!

    weak var delegate: WorkspaceTasksCollectionViewItemDelegate?
    private var currentTaskId: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupToggleRow()
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

    private func setupToggleRow() {
        guard let contentView = containerView?.contentView else { return }

        // Run Build switch + label
        runBuildSwitch = NSSwitch()
        runBuildSwitch.controlSize = .small
        runBuildSwitch.translatesAutoresizingMaskIntoConstraints = false
        runBuildSwitch.target = self
        runBuildSwitch.action = #selector(runBuildToggled(_:))
        contentView.addSubview(runBuildSwitch)

        runBuildLabel = makeToggleLabel(text: "Run Build")
        contentView.addSubview(runBuildLabel)

        // Run Tests switch + label
        runTestSuiteSwitch = NSSwitch()
        runTestSuiteSwitch.controlSize = .small
        runTestSuiteSwitch.translatesAutoresizingMaskIntoConstraints = false
        runTestSuiteSwitch.target = self
        runTestSuiteSwitch.action = #selector(runTestSuiteToggled(_:))
        contentView.addSubview(runTestSuiteSwitch)

        runTestSuiteLabel = makeToggleLabel(text: "Run Tests")
        contentView.addSubview(runTestSuiteLabel)

        // Constraints: pin toggle row above repository/date labels (bottom=38 from contentView)
        NSLayoutConstraint.activate([
            // Run Build switch
            runBuildSwitch.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            runBuildSwitch.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -36),

            // Run Build label (centered vertically with switch)
            runBuildLabel.leadingAnchor.constraint(equalTo: runBuildSwitch.trailingAnchor, constant: 6),
            runBuildLabel.centerYAnchor.constraint(equalTo: runBuildSwitch.centerYAnchor),

            // Run Tests switch (to the right of Build label with spacing)
            runTestSuiteSwitch.leadingAnchor.constraint(equalTo: runBuildLabel.trailingAnchor, constant: 20),
            runTestSuiteSwitch.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -36),

            // Run Tests label
            runTestSuiteLabel.leadingAnchor.constraint(equalTo: runTestSuiteSwitch.trailingAnchor, constant: 6),
            runTestSuiteLabel.centerYAnchor.constraint(equalTo: runTestSuiteSwitch.centerYAnchor),
        ])
    }

    private func makeToggleLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = NSColor.Sphinx.SecondaryText
        label.font = NSFont(name: "Roboto-Regular", size: 11) ?? .systemFont(ofSize: 11)
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        return label
    }

    func render(with task: WorkspaceTask) {
        currentTaskId = task.id
        let isTodo = task.status == "TODO"

        titleLabel.stringValue = task.title
        statusLabel.stringValue = task.status.replacingOccurrences(of: "_", with: " ").capitalized
        statusPillBox.fillColor = colorForStatus(task.status)
        priorityLabel.stringValue = task.priority.capitalized
        priorityPillBox.fillColor = colorForPriority(task.priority)
        repositoryLabel.stringValue = task.repositoryName ?? ""
        updatedAtLabel.stringValue = formattedDate(task.updatedAt)

        // Toggle state
        runBuildSwitch?.state = task.runBuild ? .on : .off
        runTestSuiteSwitch?.state = task.runTestSuite ? .on : .off

        // Disable and dim when not TODO
        runBuildSwitch?.isEnabled = isTodo
        runTestSuiteSwitch?.isEnabled = isTodo
        let alpha: CGFloat = isTodo ? 1.0 : 0.4
        runBuildSwitch?.alphaValue = alpha
        runBuildLabel?.alphaValue = alpha
        runTestSuiteSwitch?.alphaValue = alpha
        runTestSuiteLabel?.alphaValue = alpha
    }

    @objc private func runBuildToggled(_ sender: NSSwitch) {
        guard let taskId = currentTaskId else { return }
        delegate?.taskItem(self, didToggleRunBuild: sender.state == .on, for: taskId)
    }

    @objc private func runTestSuiteToggled(_ sender: NSSwitch) {
        guard let taskId = currentTaskId else { return }
        delegate?.taskItem(self, didToggleRunTestSuite: sender.state == .on, for: taskId)
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

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM dd, yyyy"
            return displayFormatter.string(from: date)
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM dd, yyyy"
            return displayFormatter.string(from: date)
        }

        return dateString
    }
}
