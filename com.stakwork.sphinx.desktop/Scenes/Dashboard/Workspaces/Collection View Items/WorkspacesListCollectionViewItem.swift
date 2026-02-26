//
//  WorkspacesListCollectionViewItem.swift
//  Sphinx
//
//  Created on 2025-02-19.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa
import SDWebImage

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

    private var workspaceImageView: AspectFillNSImageView!
    private var currentSlug: String?

    private static var placeholderImage: NSImage? = {
        return NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
            .flatMap { $0.image(withTintColor: NSColor.Sphinx.SecondaryText) }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupImageView()
        setupViews()
    }

    private func setupImageView() {
        workspaceImageView = AspectFillNSImageView()
        workspaceImageView.translatesAutoresizingMaskIntoConstraints = false
        workspaceImageView.wantsLayer = true
        workspaceImageView.radius = 3
        workspaceImageView.gravity = .resizeAspectFill
        workspaceImageView.image = Self.placeholderImage
        view.addSubview(workspaceImageView)

        NSLayoutConstraint.activate([
            workspaceImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            workspaceImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            workspaceImageView.widthAnchor.constraint(equalToConstant: 40),
            workspaceImageView.heightAnchor.constraint(equalToConstant: 40)
        ])
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
        workspaceImageView.sd_cancelCurrentImageLoad()
        workspaceImageView.image = Self.placeholderImage
        currentSlug = item.slug

        nameLabel.stringValue = item.name
        roleLabel.stringValue = item.role
        membersLabel.stringValue = "Members: \(item.memberCount)"

        loadWorkspaceImage(forSlug: item.slug)
    }

    private func loadWorkspaceImage(forSlug slug: String?) {
        guard let slug = slug else { return }

        if let cachedUrl = WorkspaceImageCache.shared.getImageUrl(forSlug: slug),
           let url = URL(string: cachedUrl) {
            workspaceImageView.sd_setImage(with: url, placeholderImage: Self.placeholderImage, options: [.lowPriority])
            return
        }

        API.sharedInstance.fetchWorkspaceImageWithAuth(
            slug: slug,
            callback: { [weak self] imageUrl in
                DispatchQueue.main.async {
                    guard let self = self, self.currentSlug == slug else { return }
                    if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
                        self.workspaceImageView.sd_setImage(
                            with: url,
                            placeholderImage: Self.placeholderImage,
                            options: [.lowPriority]
                        )
                    } else {
                        self.workspaceImageView.image = Self.placeholderImage
                    }
                }
            },
            errorCallback: { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.currentSlug == slug else { return }
                    self.workspaceImageView.image = Self.placeholderImage
                }
            }
        )
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
