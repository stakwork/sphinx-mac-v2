//
//  GraphListViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 30/10/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class GraphListViewController: NSViewController {    
    
    @IBOutlet weak var graphScrollView: NSScrollView!
    @IBOutlet weak var graphCollectionView: NSCollectionView!
    @IBOutlet weak var noResultsFoundLabel: NSTextField!
    
    var contentItemObjects: [ContentItem] = []

    private var currentDataSnapshot: DataSourceSnapshot!
    private var dataSource: DataSource!
    
    let dataSourceQueue = DispatchQueue(label: "contentItem.datasourceQueue", attributes: .concurrent)
    
    var graphResultsController: NSFetchedResultsController<ContentItem>!
    
    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
    
    public enum RightClickedItemActions : Int {
        case delete
        case moveToTop
    }
    
    static func instantiate() -> GraphListViewController {
        let viewController = StoryboardScene.Dashboard.graphListViewController.instantiate()
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadFeedsList()
        listenToGraphLabelChange()
    }
    
    func listenToGraphLabelChange() {
        NotificationCenter.default.addObserver(
            forName: .onGraphLabelChanged,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] (n: Notification) in
            DispatchQueue.main.async {
                self?.updateHeaderTitle()
            }
        }
    }
    
    func updateHeaderTitle() {
        guard let collectionView = graphCollectionView else { return }
        
        // Invalidate the supplementary views
        collectionView.collectionViewLayout?.invalidateLayout()
        
        // Reload the section headers
        let indexSet = IndexSet(integer: 0) // Assuming section 0
        collectionView.reloadSections(indexSet)
    }
    
    func loadFeedsList() {
        resetFetchResultsController()
        registerViews()
        configureCollectionView()
        configureDataSource()
        configureFetchResultsController()
    }
    
    func resetFetchResultsController() {
        graphResultsController?.delegate = nil
        graphResultsController = nil
    }
    
    func configureFetchResultsController() {
        ///Feeds results controller
        let feedsFetchRequest = ContentItem.FetchRequests.all()

        graphResultsController = NSFetchedResultsController(
            fetchRequest: feedsFetchRequest,
            managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        graphResultsController.delegate = self
        
        do {
            try graphResultsController.performFetch()
        } catch {}
    }
}

// MARK: - Layout & Data Structure
@available(macOS 10.15.1, *)
extension GraphListViewController {
    enum CollectionViewSection: Int, CaseIterable {
        case all
    }
    
    struct DataSourceItem: Hashable {
        
        var id: UUID
        var value: String
        var type: String
        var date: Date
        var status: Int16
        var errorMessage: String?
        var projectId: String?

        init(
            id: UUID,
            value: String,
            type: String,
            date: Date,
            status: Int16,
            errorMessage: String?,
            projectId: String?
        )
        {
            self.id = id
            self.value = value
            self.type = type
            self.date = date
            self.status = status
            self.errorMessage = errorMessage
            self.projectId = projectId
        }
        
        var statusString : String {
            get {
                switch(status) {
                case 1:
                    return "Uploaded"
                case 2:
                    return "Processing"
                case 3:
                    return "Completed"
                case 4:
                    return "Failed"
                default:
                    return "On Queue"
                }
            }
        }
        
        var typeDescription : String {
            get {
                switch(type) {
                case "image":
                    return "Image File"
                case "video":
                    return "Video File"
                case "fileURL":
                    return "Local File"
                case "externalURL":
                    return "External URL"
                case "text":
                    return "Text item"
                default:
                    return "Text item"
                }
            }
        }
        
        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            let isEqual =
                lhs.id == rhs.id &&
                lhs.value == rhs.value &&
                lhs.type == rhs.type &&
                lhs.date == rhs.date &&
                lhs.status == rhs.status &&
                lhs.projectId == rhs.projectId
            
            return isEqual
         }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(value)
            hasher.combine(type)
            hasher.combine(date)
            hasher.combine(status)
            hasher.combine(projectId)
        }
    }


    typealias CollectionViewCell = GraphListCollectionViewItem
    typealias CellDataItem = DataSourceItem
    
    @available(macOS 10.15.1, *)
    typealias DataSource = NSCollectionViewDiffableDataSource<CollectionViewSection, CellDataItem>
    
    @available(macOS 10.15.1, *)
    typealias DataSourceSnapshot = NSDiffableDataSourceSnapshot<CollectionViewSection, CellDataItem>
}

// MARK: - Collection View Configuration and View Registration
extension GraphListViewController {

    func registerViews() {
        if let nib = CollectionViewCell.nib {
            graphCollectionView.register(
                nib,
                forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: CollectionViewCell.reuseID)
            )
        }
        
        graphCollectionView.register(
            FeedListHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView")
        )
    }


    func configureCollectionView() {
        graphCollectionView.collectionViewLayout = makeLayout()
        graphCollectionView.delegate = self
    }
}

// MARK: - Layout Composition
extension GraphListViewController {

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

// MARK: - Private Helpers
extension GraphListViewController {
    
    func forceReload() {
        dataSource = nil
        
        configureDataSource()
    }
    
    func reloadCollectionView() {
        loadFeedsList()
    }
    
    func configureDataSource() {
        guard let _ = graphCollectionView else {
            return
        }
        
        makeDataSource()

        updateSnapshot()
    }
    
    func makeDataSource() {
        if let _ = dataSource {
            return
        }
        
        guard let feedsCollectionView = graphCollectionView else {
            return
        }
        
        let dataSource = DataSource(
            collectionView: feedsCollectionView,
            itemProvider: makeCellProvider()
        )
        
        dataSource.supplementaryViewProvider = {(collectionView, kind, indexPath) in
            if kind == NSCollectionView.elementKindSectionHeader {
                guard let headerView = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView"),
                    for: indexPath
                ) as? (NSView & NSCollectionViewElement) else {
                    return nil
                }
                
                let customTitle = UserData.sharedInstance.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel)
                let title = (customTitle != nil) ? "\(customTitle!) Items" : "Graph Items"
                
                (headerView as? FeedListHeaderView)?.renderWith(
                    title: title,
                    backgroundColor: NSColor.Sphinx.Body,
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
extension GraphListViewController {

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

                cell.render(
                    with: dataSourceItem,
                    and: self
                )

                return cell
            }
        }
    }
}

// MARK: - Data Source Snapshot
extension GraphListViewController {

    func updateSnapshot(
        completion: (() -> ())? = nil
    ) {
        let items = self.contentItemObjects.enumerated().map { (index, element) in
            
            DataSourceItem(
                id: element.uuid ?? UUID(),
                value: element.value,
                type: element.type,
                date: element.lastProcessedAt ?? element.date,
                status: element.status,
                errorMessage: element.errorMessage,
                projectId: element.projectId
            )
        }
        
        updateSnapshot(with: items, completion: completion)
    }
    
    func updateSnapshot(
        with items: [DataSourceItem],
        completion: (() -> ())? = nil
    ) {
        makeDataSource()
        
        guard let _ = dataSource else {
            return
        }
        
        DispatchQueue.main.async {
            var snapshot = DataSourceSnapshot()

            snapshot.appendSections(CollectionViewSection.allCases)
            
            snapshot.appendItems(items, toSection: .all)
            
            self.dataSource.apply(snapshot, animatingDifferences: false) {
                
                let sectionIndex = CollectionViewSection.all.rawValue
                self.graphCollectionView.collectionViewLayout?.invalidateLayout()
                self.graphCollectionView.reloadSections(IndexSet(integer: sectionIndex))
                
                self.graphScrollView.isHidden = items.isEmpty
                self.noResultsFoundLabel.isHidden = !items.isEmpty
                
                completion?()
            }
        }
    }
}

extension GraphListViewController : NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
//        collectionView.deselectAll(nil)
//        
//        if let indexPath = indexPaths.first {
//            DelayPerformedHelper.performAfterDelay(seconds: 0.05, completion: {
//                let item = self.dataSource.itemIdentifier(for: indexPath)
//                
//                guard let item = item else {
//                    return
//                }
//                self.delegate?.didClickRowWith(contentFeedId: item.feedId)
//            })
//        }
    }
}

extension GraphListViewController : NSFetchedResultsControllerDelegate {
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        if
            let resultController = controller as? NSFetchedResultsController<NSManagedObject>,
            let firstSection = resultController.sections?.first {
            
            if let objects = firstSection.objects as? [ContentItem] {
                self.contentItemObjects = objects
            }
            
            updateSnapshot(completion: {})
        }
    }
}

extension GraphListViewController : ContentItemCollectionViewDelegate {
    func didRightClickOn(item: NSCollectionViewItem) {
        if let indexPath = graphCollectionView.indexPath(for: item) {
            let item = self.contentItemObjects[indexPath.item] as ContentItem
            
            showContextMenuFor(item: item)
        }
    }
    
    func showContextMenuFor(
        item: ContentItem
    ) {
        let contextMenu = NSMenu(title: "Context Menu")
        contextMenu.autoenablesItems = true
        contextMenu.items = []
        var newItems = [NSMenuItem]()

        let deleteItem = NSMenuItem(
            title: "Delete Item",
            action: #selector(self.handleMenuItemClick(_:)),
            keyEquivalent: ""
        )
        deleteItem.representedObject = item
        deleteItem.target = self
        deleteItem.tag = RightClickedItemActions.delete.rawValue
        deleteItem.isEnabled = true
        
        newItems.append(deleteItem)
        
//        let moveToTopItem = NSMenuItem(
//            title: "Move to Top",
//            action: #selector(self.handleMenuItemClick(_:)),
//            keyEquivalent: ""
//        )
//        moveToTopItem.representedObject = item
//        moveToTopItem.target = self
//        moveToTopItem.tag = RightClickedItemActions.moveToTop.rawValue
//        moveToTopItem.isEnabled = true
//        
//        newItems.append(moveToTopItem)
        
        if newItems.isEmpty {
            return
        }
        
        contextMenu.items = newItems
        
        contextMenu.popUp(
            positioning: contextMenu.item(at: 0),
            at: NSEvent.mouseLocation,
            in: nil
        )
    }
    
    @objc func handleMenuItemClick(_ sender: NSMenuItem) {
        if let action = RightClickedItemActions(rawValue: sender.tag) {
            guard let item = (sender.representedObject as? ContentItem) else {
                return
            }
            switch action {
            case .delete:
                CoreDataManager.sharedManager.deleteObject(object: item)
                break
            case .moveToTop:
                if let lowestOrderItem = ContentItem.getLowestItemOrder()?.order {
                    item.order = lowestOrderItem - 1
                    item.managedObjectContext?.saveContext()
                }
                break
            }
        }
    }
}

extension GraphListViewController : FeedListHeaderViewDelegate {
    func didClickRefreshButton(completion: @escaping () -> ()) {
        ContentItemsManager.shared.startBackgroundProcessing(completion: completion)
    }
}
