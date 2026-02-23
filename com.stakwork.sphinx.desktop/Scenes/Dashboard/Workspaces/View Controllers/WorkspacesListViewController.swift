//
//  WorkspacesListViewController.swift
//  Sphinx
//
//  Created on 2025-02-19.
//  Copyright © 2025 Sphinx. All rights reserved.
//

import Cocoa

class WorkspacesListViewController: NSViewController {

    @IBOutlet weak var workspacesScrollView: NSScrollView!
    @IBOutlet weak var workspacesCollectionView: NSCollectionView!
    @IBOutlet weak var noResultsFoundLabel: NSTextField!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!

    var workspaces: [Workspace] = []
    private var allWorkspaces: [Workspace] = []

    private var currentDataSnapshot: DataSourceSnapshot!
    private var dataSource: DataSource!
    
    private var searchTerm: String? = nil

    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )

    private var isLoading = false {
        didSet {
            if isLoading {
                loadingWheel.startAnimation(nil)
                loadingWheel.isHidden = false
                noResultsFoundLabel.isHidden = true
            } else {
                loadingWheel.stopAnimation(nil)
                loadingWheel.isHidden = true
            }
        }
    }

    static func instantiate() -> WorkspacesListViewController {
        let viewController = StoryboardScene.Dashboard.workspacesListViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        loadWorkspaces()
    }

    func setupViews() {
        registerViews()
        configureCollectionView()
        configureDataSource()
    }

    func loadWorkspaces() {
        guard !isLoading else { return }

        isLoading = true
        noResultsFoundLabel.isHidden = true

        API.sharedInstance.fetchWorkspacesWithAuth(
            callback: { [weak self] workspaces in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.allWorkspaces = workspaces
                    self?.workspaces = workspaces
                    self?.updateSnapshot()
                }
            },
            errorCallback: { [weak self] in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.allWorkspaces = []
                    self?.workspaces = []
                    self?.updateSnapshot()
                }
            }
        )
    }
}

// MARK: - Layout & Data Structure
extension WorkspacesListViewController {
    enum CollectionViewSection: Int, CaseIterable {
        case all
    }

    struct DataSourceItem: Hashable {
        var id: String
        var name: String
        var role: String
        var memberCount: Int

        init(workspace: Workspace) {
            self.id = workspace.id
            self.name = workspace.name
            self.role = workspace.formattedRole
            self.memberCount = workspace.memberCount
        }

        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            return lhs.id == rhs.id &&
                   lhs.name == rhs.name &&
                   lhs.role == rhs.role &&
                   lhs.memberCount == rhs.memberCount
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(name)
            hasher.combine(role)
            hasher.combine(memberCount)
        }
    }

    typealias CollectionViewCell = WorkspacesListCollectionViewItem
    typealias CellDataItem = DataSourceItem

    typealias DataSource = NSCollectionViewDiffableDataSource<CollectionViewSection, CellDataItem>
    typealias DataSourceSnapshot = NSDiffableDataSourceSnapshot<CollectionViewSection, CellDataItem>
}

// MARK: - Collection View Configuration and View Registration
extension WorkspacesListViewController {

    func registerViews() {
        if let nib = CollectionViewCell.nib {
            workspacesCollectionView.register(
                nib,
                forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: CollectionViewCell.reuseID)
            )
        }

        workspacesCollectionView.register(
            FeedListHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView")
        )
    }

    func configureCollectionView() {
        workspacesCollectionView.collectionViewLayout = makeLayout()
        workspacesCollectionView.delegate = self
    }
}

// MARK: - Layout Composition
extension WorkspacesListViewController {

    func makeSectionHeader() -> NSCollectionLayoutBoundarySupplementaryItem {
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(50)
        )

        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: NSCollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    func makeListSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )

        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = itemContentInsets

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(Constants.kChatListRowHeight)
        )

        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .none
        section.contentInsets = NSDirectionalEdgeInsets(top: 0.0, leading: 0, bottom: 0.0, trailing: 0)

        section.boundarySupplementaryItems = [makeSectionHeader()]

        return section
    }

    func makeSectionProvider() -> NSCollectionViewCompositionalLayoutSectionProvider {
        { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            switch CollectionViewSection(rawValue: sectionIndex) {
            case .all:
                return self.makeListSection()
            case nil:
                return nil
            }
        }
    }

    func makeLayout() -> NSCollectionViewLayout {
        let layoutConfiguration = NSCollectionViewCompositionalLayoutConfiguration()

        let layout = NSCollectionViewCompositionalLayout(
            sectionProvider: makeSectionProvider()
        )

        layout.configuration = layoutConfiguration

        return layout
    }
}

// MARK: - Data Source Configuration
extension WorkspacesListViewController {

    func configureDataSource() {
        guard let _ = workspacesCollectionView else {
            return
        }

        makeDataSource()
    }

    func makeDataSource() {
        if let _ = dataSource {
            return
        }

        guard let collectionView = workspacesCollectionView else {
            return
        }

        let dataSource = DataSource(
            collectionView: collectionView,
            itemProvider: makeCellProvider()
        )

        dataSource.supplementaryViewProvider = { (collectionView, kind, indexPath) in
            if kind == NSCollectionView.elementKindSectionHeader {
                guard let headerView = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView"),
                    for: indexPath
                ) as? (NSView & NSCollectionViewElement) else {
                    return nil
                }

                (headerView as? FeedListHeaderView)?.renderWith(
                    title: "Workspaces",
                    showRefreshButton: true,
                    delegate: self
                )

                return headerView
            }
            return nil
        }

        self.dataSource = dataSource
    }
}

// MARK: - Data Source View Providers
extension WorkspacesListViewController {

    func makeCellProvider() -> DataSource.ItemProvider {
        { [weak self] (collectionView, indexPath, dataSourceItem) -> NSCollectionViewItem? in
            guard let _ = self else {
                return nil
            }

            let section = CollectionViewSection.allCases[indexPath.section]

            switch section {
            case .all:
                guard let cell = collectionView.makeItem(
                    withIdentifier: NSUserInterfaceItemIdentifier(
                        rawValue: CollectionViewCell.reuseID
                    ),
                    for: indexPath
                ) as? CollectionViewCell else { return nil }

                cell.render(with: dataSourceItem)

                return cell
            }
        }
    }
}

// MARK: - Data Source Snapshot
extension WorkspacesListViewController {

    func updateSnapshot(completion: (() -> ())? = nil) {
        let items = workspaces.map { DataSourceItem(workspace: $0) }
        updateSnapshot(with: items, completion: completion)
    }

    func updateSnapshot(
        with items: [DataSourceItem],
        completion: (() -> ())? = nil
    ) {
        makeDataSource()

        guard let dataSource = dataSource else {
            return
        }

        DispatchQueue.main.async {
            var snapshot = DataSourceSnapshot()

            snapshot.appendSections(CollectionViewSection.allCases)
            snapshot.appendItems(items, toSection: .all)

            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }

                // Keep scroll view visible so header with refresh button is always accessible
                self.workspacesScrollView.isHidden = false

                let showNoResults = items.isEmpty && !self.isLoading
                self.noResultsFoundLabel.isHidden = !showNoResults

                // Bring label to front so it's visible above the scroll view
                if showNoResults {
                    self.noResultsFoundLabel.superview?.addSubview(
                        self.noResultsFoundLabel,
                        positioned: .above,
                        relativeTo: self.workspacesScrollView
                    )
                }

                completion?()
            }
        }
    }
}

// MARK: - NSCollectionViewDelegate
extension WorkspacesListViewController: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)

        if let indexPath = indexPaths.first {
            let workspace = workspaces[indexPath.item]
            print("Selected workspace: \(workspace.name)")
            // TODO: Handle workspace selection
        }
    }
}

// MARK: - FeedListHeaderViewDelegate
extension WorkspacesListViewController: FeedListHeaderViewDelegate {
    func didClickRefreshButton(completion: @escaping () -> ()) {
        loadWorkspaces()
        completion()
    }
}
// MARK: - Search/Filter
extension WorkspacesListViewController {
    func filterWorkspaces(term: String) {
        searchTerm = term
        
        let filtered = term.isEmpty
            ? allWorkspaces
            : allWorkspaces.filter { $0.name.localizedCaseInsensitiveContains(term) }
        
        let items = filtered.map { DataSourceItem(workspace: $0) }
        updateSnapshot(with: items)
    }
}
