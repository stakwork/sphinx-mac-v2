//
//  WorkspaceTasksDashboardViewController.swift
//  Sphinx
//
//  Created on 2025-02-26.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

class WorkspaceTasksDashboardViewController: NSViewController {

    @IBOutlet weak var workspaceNameLabel: NSTextField!
    @IBOutlet weak var segmentedControl: ChatsSegmentedControl!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    @IBOutlet weak var noResultsFoundLabel: NSTextField!
    @IBOutlet weak var errorLabel: NSTextField!

    var workspace: Workspace?
    private var tasks: [WorkspaceTask] = []
    private var includeArchived = false
    private var isLoading = false
    
    private var dataSource: NSCollectionViewDiffableDataSource<Int, WorkspaceTask>!

    static func instantiate(workspace: Workspace) -> WorkspaceTasksDashboardViewController {
        let vc = StoryboardScene.Dashboard.workspaceTasksDashboardViewController.instantiate()
        vc.workspace = workspace
        return vc
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWorkspaceNameLabel()
        setupCollectionView()
        setupSegmentedControl()
        loadTasks()
    }

    private func setupWorkspaceNameLabel() {
        workspaceNameLabel.stringValue = workspace?.name ?? ""
        workspaceNameLabel.textColor = NSColor.Sphinx.Text
        workspaceNameLabel.font = NSFont(name: "Roboto-Medium", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium)
    }

    func resizeSubviews(frame: NSRect) {
        view.frame = frame
        collectionView.frame = collectionView.superview?.bounds ?? frame
    }

    private func setupSegmentedControl() {
        segmentedControl.configureFromOutlet(
            buttonTitles: ["Active", "Archived"],
            delegate: self,
            initialSelectedIndex: 0
        )
    }
    
    private func setupCollectionView() {
        // Register the cell
        collectionView.register(
            WorkspaceTasksCollectionViewItem.nib,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(WorkspaceTasksCollectionViewItem.reuseID)
        )
        
        // Configure layout with 105pt row height for task rows
        let layout = NSCollectionViewCompositionalLayout { (sectionIndex, environment) -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(105)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(105)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            let section = NSCollectionLayoutSection(group: group)
            return section
        }
        
        collectionView.collectionViewLayout = layout
        
        // Setup diffable data source
        dataSource = NSCollectionViewDiffableDataSource<Int, WorkspaceTask>(
            collectionView: collectionView
        ) { (collectionView, indexPath, task) -> NSCollectionViewItem? in
            let item = collectionView.makeItem(
                withIdentifier: NSUserInterfaceItemIdentifier(WorkspaceTasksCollectionViewItem.reuseID),
                for: indexPath
            ) as? WorkspaceTasksCollectionViewItem
            
            item?.render(with: task)
            return item
        }
    }
    
    private func updateSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, WorkspaceTask>()
        snapshot.appendSections([0])
        snapshot.appendItems(tasks, toSection: 0)
        
        // Apply snapshot without animation when switching tabs to prevent flash
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            // Only show collection view after snapshot has been applied
            DispatchQueue.main.async {
                self?.collectionView.isHidden = false
            }
        }
    }

    private func loadTasks() {
        guard let workspaceId = workspace?.id, !isLoading else { return }
        isLoading = true
        noResultsFoundLabel.isHidden = true
        errorLabel.isHidden = true
        collectionView.isHidden = true  // Hide collection view while loading
        loadingWheel.startAnimation(nil)
        loadingWheel.isHidden = false

        API.sharedInstance.fetchTasksWithAuth(
            workspaceId: workspaceId,
            includeArchived: includeArchived,
            callback: { [weak self] tasks in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.loadingWheel.stopAnimation(nil)
                    self?.loadingWheel.isHidden = true
                    self?.tasks = tasks
                    self?.updateSnapshot()
                    self?.noResultsFoundLabel.isHidden = !tasks.isEmpty
                }
            },
            errorCallback: { [weak self] in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.loadingWheel.stopAnimation(nil)
                    self?.loadingWheel.isHidden = true
                    self?.collectionView.isHidden = false  // Show collection view even on error
                    self?.errorLabel.isHidden = false
                    self?.errorLabel.stringValue = "Failed to load tasks. Please try again."
                }
            }
        )
    }
}

extension WorkspaceTasksDashboardViewController: ChatsSegmentedControlDelegate {
    func segmentedControlDidSwitch(_ segmentedControl: ChatsSegmentedControl, to index: Int) {
        includeArchived = (index == 1)
        loadTasks()
    }
}
