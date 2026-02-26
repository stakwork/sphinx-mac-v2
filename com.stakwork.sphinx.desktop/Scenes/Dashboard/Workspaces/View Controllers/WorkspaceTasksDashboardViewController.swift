//
//  WorkspaceTasksDashboardViewController.swift
//  Sphinx
//
//  Created on 2025-02-26.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

class WorkspaceTasksDashboardViewController: NSViewController {

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
        setupCollectionView()
        setupSegmentedControl()
        loadTasks()
    }

    func resizeSubviews(frame: NSRect) {
        view.frame = frame
        collectionView.frame = collectionView.superview?.bounds ?? frame
    }

    private func setupSegmentedControl() {
        segmentedControl.configureFromOutlet(
            buttonTitles: ["Active", "Archived"],
            delegate: self
        )
    }
    
    private func setupCollectionView() {
        // Register the cell
        collectionView.register(
            WorkspaceTasksCollectionViewItem.nib,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(WorkspaceTasksCollectionViewItem.reuseID)
        )
        
        // Configure layout matching WorkspacesListViewController pattern
        let layout = NSCollectionViewCompositionalLayout { (sectionIndex, environment) -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(Constants.kChatListRowHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(Constants.kChatListRowHeight)
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
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    private func loadTasks() {
        guard let workspaceId = workspace?.id, !isLoading else { return }
        isLoading = true
        noResultsFoundLabel.isHidden = true
        errorLabel.isHidden = true
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
