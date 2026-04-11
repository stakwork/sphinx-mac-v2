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
        collectionView.register(
            WorkspaceTasksCollectionViewItem.nib,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(WorkspaceTasksCollectionViewItem.reuseID)
        )

        // Row height increased to 135 to accommodate the toggle row
        let rowHeight: CGFloat = 135

        let layout = NSCollectionViewCompositionalLayout { (_, _) -> NSCollectionLayoutSection? in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(rowHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(rowHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            return NSCollectionLayoutSection(group: group)
        }

        collectionView.collectionViewLayout = layout

        dataSource = NSCollectionViewDiffableDataSource<Int, WorkspaceTask>(
            collectionView: collectionView
        ) { [weak self] (collectionView, indexPath, task) -> NSCollectionViewItem? in
            let item = collectionView.makeItem(
                withIdentifier: NSUserInterfaceItemIdentifier(WorkspaceTasksCollectionViewItem.reuseID),
                for: indexPath
            ) as? WorkspaceTasksCollectionViewItem

            item?.delegate = self
            item?.render(with: task)
            return item
        }
    }

    private func updateSnapshot(animating: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, WorkspaceTask>()
        snapshot.appendSections([0])
        snapshot.appendItems(tasks, toSection: 0)

        dataSource.apply(snapshot, animatingDifferences: animating) { [weak self] in
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
        collectionView.isHidden = true
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
                    self?.collectionView.isHidden = false
                    self?.errorLabel.isHidden = false
                    self?.errorLabel.stringValue = "Failed to load tasks. Please try again."
                }
            }
        )
    }

    // MARK: - Optimistic Toggle Helpers

    private func updateTask(
        id taskId: String,
        params: [String: AnyObject],
        optimisticUpdate: @escaping (inout WorkspaceTask) -> Void
    ) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }

        // Capture snapshot before mutation for potential revert
        let previousTask = tasks[index]

        // Apply optimistic update to local state
        var updatedTask = tasks[index]
        optimisticUpdate(&updatedTask)
        tasks[index] = updatedTask
        updateSnapshot()

        API.sharedInstance.updateTaskWithAuth(
            taskId: taskId,
            params: params,
            callback: { /* success — optimistic state already applied */ },
            errorCallback: { [weak self] in
                // Revert on failure
                DispatchQueue.main.async {
                    guard let self = self,
                          let revertIndex = self.tasks.firstIndex(where: { $0.id == taskId }) else { return }
                    self.tasks[revertIndex] = previousTask
                    self.updateSnapshot()
                }
            }
        )
    }
}

// MARK: - ChatsSegmentedControlDelegate

extension WorkspaceTasksDashboardViewController: ChatsSegmentedControlDelegate {
    func segmentedControlDidSwitch(_ segmentedControl: ChatsSegmentedControl, to index: Int) {
        includeArchived = (index == 1)
        loadTasks()
    }
}

// MARK: - WorkspaceTasksCollectionViewItemDelegate

extension WorkspaceTasksDashboardViewController: WorkspaceTasksCollectionViewItemDelegate {

    func taskItem(
        _ item: WorkspaceTasksCollectionViewItem,
        didToggleRunBuild value: Bool,
        for taskId: String
    ) {
        updateTask(
            id: taskId,
            params: ["runBuild": value as AnyObject]
        ) { task in
            task.runBuild = value
        }
    }

    func taskItem(
        _ item: WorkspaceTasksCollectionViewItem,
        didToggleRunTestSuite value: Bool,
        for taskId: String
    ) {
        updateTask(
            id: taskId,
            params: ["runTestSuite": value as AnyObject]
        ) { task in
            task.runTestSuite = value
        }
    }
}
