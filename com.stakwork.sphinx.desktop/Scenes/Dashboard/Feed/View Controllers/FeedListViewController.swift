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
    
    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
    
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
        feedsResultsController?.delegate = nil
        feedsResultsController = nil
        
        registerViews()
        configureCollectionView()
        configureDataSource()
        configureFetchResultsController()
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
        var feedDescription: String?
        var feedKindValue: Int16

        init(
            feedUrl: String,
            feedId: String,
            title: String,
            authorName: String?,
            feedDescription: String?,
            feedKindValue: Int16
        )
        {
            self.feedUrl = feedUrl
            self.feedId = feedId
            self.title = title
            self.authorName = authorName
            self.feedDescription = feedDescription
            self.feedKindValue = feedKindValue
        }
        
        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            let isEqual =
                lhs.feedUrl == rhs.feedUrl &&
                lhs.feedId == rhs.feedId &&
                lhs.title == rhs.title &&
                lhs.authorName == rhs.authorName &&
                lhs.feedDescription == rhs.feedDescription &&
                lhs.feedKindValue == rhs.feedKindValue
            
            return isEqual
         }

        func hash(into hasher: inout Hasher) {
            hasher.combine(feedUrl)
            hasher.combine(feedId)
            hasher.combine(title)
            hasher.combine(authorName)
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
            heightDimension: .estimated(50)
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
        if let _ = dataSource {
            return
        }
        
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
        
        dataSource.supplementaryViewProvider = { (collectionView, kind, indexPath) in
            if kind == NSCollectionView.elementKindSectionHeader {
                guard let headerView = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: NSUserInterfaceItemIdentifier("FeedListHeaderView"),
                    for: indexPath
                ) as? (NSView & NSCollectionViewElement) else {
                    return nil
                }
                // Optionally configure the view with self?.data
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
        { [weak self] (collectionView, indexPath, chatItem) -> NSCollectionViewItem? in
            guard let self else {
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
                    with: self.contentFeedObjects[indexPath.item]
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
        configureDataSource()
        
        guard let _ = dataSource else {
            return
        }
        
        DispatchQueue.main.async {
            var snapshot = DataSourceSnapshot()

            snapshot.appendSections(CollectionViewSection.allCases)

            let items = self.contentFeedObjects.enumerated().map { (index, element) in
                
                DataSourceItem(
                    feedUrl: element.feedURL?.absoluteString ?? "",
                    feedId: element.feedID,
                    title: element.title ?? "",
                    authorName: element.authorName,
                    feedDescription: element.feedDescription,
                    feedKindValue: element.feedKindValue
                )
            }
            
            snapshot.appendItems(items, toSection: .all)
            
            self.dataSource.apply(snapshot, animatingDifferences: true) {
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
