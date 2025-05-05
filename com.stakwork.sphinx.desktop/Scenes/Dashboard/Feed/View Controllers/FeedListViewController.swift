//
//  FeedListViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol FeedListViewControllerDelegate: NSObject {
    func didClickRowWith(contentFeedId: String?)
}

class FeedListViewController: NSViewController {
    
    weak var delegate: FeedListViewControllerDelegate?

    @IBOutlet weak var feedsCollectionView: NSCollectionView!
    
    var contentFeedObjects: [ContentFeed] = []
    
    var onFeedSelected: ((ChatListCommonObject) -> Void)?
    var onContentScrolled: ((NSScrollView) -> Void)?

    private var currentDataSnapshot: DataSourceSnapshot!
    private var dataSource: DataSource!
    
    let dataSourceQueue = DispatchQueue(label: "chatList.datasourceQueue", attributes: .concurrent)
    
    var feedsResultsController: NSFetchedResultsController<ContentFeed>!
    
    var searchTimer: Timer? = nil
    
    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
    
    enum FeedMode: Int, Hashable {
        case following
        case searching
        case searchResults
    }
    
    var currentMode: FeedMode = .following
    
    static func instantiate(
        delegate: FeedListViewControllerDelegate?
    ) -> FeedListViewController {
        let viewController = StoryboardScene.Dashboard.feedListViewController.instantiate()
        viewController.delegate = delegate
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadFeedsList()
    }
    
    func loadFeedsList() {
        resetFetchResultsController()
        registerViews()
        configureCollectionView()
        configureDataSource()
        configureFetchResultsController()
    }
    
    func resetFetchResultsController() {
        feedsResultsController?.delegate = nil
        feedsResultsController = nil
    }
    
    func configureFetchResultsController() {
        ///Feeds results controller
        let feedsFetchRequest = ContentFeed.FetchRequests.default()

        feedsResultsController = NSFetchedResultsController(
            fetchRequest: feedsFetchRequest,
            managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        feedsResultsController.delegate = self
        
        do {
            try feedsResultsController.performFetch()
        } catch {}
    }
    
    func resetSearch() {
        currentMode = .following
        updateSnapshot(with: [], completion: nil)
        resetFetchResultsController()
        configureFetchResultsController()
    }
    
    func searchWith(searchQuery: String) {
        if searchQuery.isEmpty {
            resetSearch()
            return
        }
        
        currentMode = .searching
        updateSnapshot(with: [], completion: nil)
        
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(fetchRemoteResults(timer:)),
            userInfo: ["search_query": searchQuery],
            repeats: false
        )
    }
    
    @objc func fetchRemoteResults(timer: Timer) {
        if let userInfo = timer.userInfo as? [String: Any] {
            if let searchQuery = userInfo["search_query"] as? String {
                API.sharedInstance.searchForFeeds(
                    with: FeedType.Podcast,
                    matching: searchQuery
                ) { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let results):
                            
                            let items = results.map {
                                DataSourceItem(
                                    feedUrl: $0.feedURLPath,
                                    feedId: $0.feedId,
                                    title: $0.title,
                                    authorName: $0.feedDescription,
                                    imageUrl: $0.imageUrl,
                                    feedDescription: $0.feedDescription,
                                    feedKindValue: $0.feedType.rawValue
                                )
                            }
                            
                            self.currentMode = .searchResults
                            self.updateSnapshot(with: items, completion: nil)
                            
                        case .failure(_):
                            break
                        }
                    }
                }
            }
        }
    }
    
}

// MARK: - Layout & Data Structure
@available(macOS 10.15.1, *)
extension FeedListViewController {
    enum CollectionViewSection: Int, CaseIterable {
        case all
    }
    
    struct DataSourceItem: Hashable {
        
        var feedUrl: String
        var feedId: String
        var title: String
        var authorName: String?
        var imageUrl: String?
        var feedDescription: String?
        var feedKindValue: Int16

        init(
            feedUrl: String,
            feedId: String,
            title: String,
            authorName: String?,
            imageUrl: String?,
            feedDescription: String?,
            feedKindValue: Int16
        )
        {
            self.feedUrl = feedUrl
            self.feedId = feedId
            self.title = title
            self.authorName = authorName
            self.imageUrl = imageUrl
            self.feedDescription = feedDescription
            self.feedKindValue = feedKindValue
        }
        
        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            let isEqual =
                lhs.feedUrl == rhs.feedUrl &&
                lhs.feedId == rhs.feedId &&
                lhs.title == rhs.title &&
                lhs.authorName == rhs.authorName &&
                lhs.imageUrl == rhs.imageUrl &&
                lhs.feedDescription == rhs.feedDescription &&
                lhs.feedKindValue == rhs.feedKindValue
            
            return isEqual
         }

        func hash(into hasher: inout Hasher) {
            hasher.combine(feedUrl)
            hasher.combine(feedId)
            hasher.combine(title)
            hasher.combine(authorName)
            hasher.combine(imageUrl)
            hasher.combine(feedDescription)
            hasher.combine(feedKindValue)
        }
    }


    typealias CollectionViewCell = FeedListCollectionViewItem
    typealias CellDataItem = DataSourceItem
    
    @available(macOS 10.15.1, *)
    typealias DataSource = NSCollectionViewDiffableDataSource<CollectionViewSection, CellDataItem>
    
    @available(macOS 10.15.1, *)
    typealias DataSourceSnapshot = NSDiffableDataSourceSnapshot<CollectionViewSection, CellDataItem>
}

// MARK: - Collection View Configuration and View Registration
extension FeedListViewController {

    func registerViews() {
        if let nib = CollectionViewCell.nib {
            feedsCollectionView.register(
                nib,
                forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: CollectionViewCell.reuseID)
            )
        }
        
        feedsCollectionView.register(
            FeedListHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView")
        )
    }


    func configureCollectionView() {
        feedsCollectionView.collectionViewLayout = makeLayout()
        feedsCollectionView.delegate = self
    }
}

// MARK: - Layout Composition
extension FeedListViewController {

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
extension FeedListViewController {
    
    func forceReload() {
        dataSource = nil
        
        configureDataSource()
    }
    
    func reloadCollectionView() {
        loadFeedsList()
    }
    
    func configureDataSource() {
        guard let _ = feedsCollectionView else {
            return
        }
        
        dataSource = makeDataSource()

        updateSnapshot()
    }
    
    func makeDataSource() -> DataSource {
        let dataSource = DataSource(
            collectionView: feedsCollectionView,
            itemProvider: makeCellProvider()
        )
        
        dataSource.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            if kind == NSCollectionView.elementKindSectionHeader {
                guard let headerView = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView"),
                    for: indexPath
                ) as? (NSView & NSCollectionViewElement) else {
                    return nil
                }
                
                var title = "Following"
                switch(self?.currentMode) {
                case .searching:
                    title = "Searching..."
                    break
                case .searchResults:
                    title = "Search Results"
                    break
                default:
                    break
                }
                
                (headerView as? FeedListHeaderView)?.renderWith(title: title)
                
                return headerView
            }
            return nil
        }
        
        return dataSource
    }
}

// MARK: - Data Source View Providers
extension FeedListViewController {

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
                    with: dataSourceItem
                )

                return cell
            }
        }
    }
}

// MARK: - Data Source Snapshot
extension FeedListViewController {

    func updateSnapshot(
        completion: (() -> ())? = nil
    ) {
        let items = self.contentFeedObjects.enumerated().map { (index, element) in
            
            DataSourceItem(
                feedUrl: element.feedURL?.absoluteString ?? "",
                feedId: element.feedID,
                title: element.title ?? "",
                authorName: element.authorName,
                imageUrl: element.imageToShow,
                feedDescription: element.feedDescription,
                feedKindValue: element.feedKindValue
            )
        }
        
        updateSnapshot(with: items, completion: completion)
    }
    
    func updateSnapshot(
        with items: [DataSourceItem],
        completion: (() -> ())? = nil
    ) {
        guard let _ = dataSource else {
            return
        }
        
        DispatchQueue.main.async {
            var snapshot = DataSourceSnapshot()

            snapshot.appendSections(CollectionViewSection.allCases)
            
            snapshot.appendItems(items, toSection: .all)
            
            self.dataSource.apply(snapshot, animatingDifferences: false) {
                
                let sectionIndex = CollectionViewSection.all.rawValue
                self.feedsCollectionView.collectionViewLayout?.invalidateLayout()
                self.feedsCollectionView.reloadSections(IndexSet(integer: sectionIndex))
                
                completion?()
            }
        }
    }
}

extension FeedListViewController : NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        
        collectionView.deselectAll(nil)
        
        if let indexPath = indexPaths.first {
            DelayPerformedHelper.performAfterDelay(seconds: 0.05, completion: {
                let contentFeed = self.contentFeedObjects[indexPath.item]
                self.delegate?.didClickRowWith(contentFeedId: contentFeed.feedID)
            })
        }
    }
}

extension FeedListViewController : NSFetchedResultsControllerDelegate {
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        if
            let resultController = controller as? NSFetchedResultsController<NSManagedObject>,
            let firstSection = resultController.sections?.first {
            
            if let objects = firstSection.objects as? [ContentFeed] {
                self.contentFeedObjects = objects
            }
            
            updateSnapshot(completion: {})
        }
    }
}
