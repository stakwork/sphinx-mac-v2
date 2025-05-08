//
//  FeedListenDashboardViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 06/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class FeedListenDashboardViewController: NSViewController {
    
    @IBOutlet weak var feedScrollView: NSScrollView!
    @IBOutlet weak var feedCollectionView: NSCollectionView!
    
    var allPodcastFeeds: [PodcastFeed] = []
    var followedPodcastFeeds: [PodcastFeed] = []
    
    var interSectionSpacing: CGFloat!

    var onPodcastEpisodeCellSelected: ((String) -> Void)!
//    var onSubscribedPodcastFeedCellSelected: ((PodcastFeed) -> Void)!
//    var onNewResultsFetched: ((Int) -> Void)!
//    var onContentScrolled: ((UIScrollView) -> Void)?

    private var managedObjectContext: NSManagedObjectContext!
    private var fetchedResultsController: NSFetchedResultsController<ContentFeed>!
    private var currentDataSnapshot: DataSourceSnapshot!
    private var dataSource: DataSource!

    private let itemContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: 0,
        bottom: 0,
        trailing: 0
    )
    
    static func instantiate(
        managedObjectContext: NSManagedObjectContext = CoreDataManager.sharedManager.persistentContainer.viewContext,
        interSectionSpacing: CGFloat = 5.0,
        onPodcastEpisodeCellSelected: @escaping ((String) -> Void) = { _ in }
    ) -> FeedListenDashboardViewController {
        let viewController = StoryboardScene.Dashboard.feedListenDashboardViewController.instantiate()
        viewController.interSectionSpacing = interSectionSpacing
        viewController.onPodcastEpisodeCellSelected = onPodcastEpisodeCellSelected
        viewController.fetchedResultsController = Self.makeFetchedResultsController(using: managedObjectContext)
        viewController.fetchedResultsController.delegate = viewController
        return viewController
    }
    
}

// MARK: - Lifecycle
extension FeedListenDashboardViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        registerViews(for: feedCollectionView)
        configure(feedCollectionView)
        configureDataSource(for: feedCollectionView)
        
        feedScrollView.contentView.backgroundColor = NSColor.Sphinx.Body
        feedScrollView.backgroundColor = NSColor.Sphinx.Body
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        NotificationCenter.default.removeObserver(self, name: .refreshFeedUI, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(forceItemsRefresh), name: .refreshFeedUI, object: nil)
        
        fetchItems()
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        
        NotificationCenter.default.removeObserver(self, name: .refreshFeedUI, object: nil)
    }
    
    @objc func forceItemsRefresh() {
        DispatchQueue.main.async { [weak self] in
            if let feeds = self?.allPodcastFeeds {
                self?.updateWithNew(
                    podcastFeeds: feeds
                )
                
//                self?.onNewResultsFetched(feeds.count)
            }
        }
    }
}

// MARK: - Collection View Configuration and View Registration
extension FeedListenDashboardViewController {

    func registerViews(for collectionView: NSCollectionView) {
        if let nib = CollectionViewCell.nib {
            collectionView.register(
                nib,
                forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: CollectionViewCell.reuseID)
            )
        }
        
        collectionView.register(
            FeedSectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: NSUserInterfaceItemIdentifier("FeedSectionHeaderView")
        )
    }


    func configure(_ collectionView: NSCollectionView) {
        collectionView.collectionViewLayout = makeLayout()
        collectionView.delegate = self
        collectionView.backgroundColors = [NSColor.Sphinx.Body]
        collectionView.wantsLayer = true
        collectionView.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
    }
    
//    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
//        onContentScrolled?(scrollView)
//    }
}

extension FeedListenDashboardViewController : NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        collectionView.deselectAll(nil)
        
        if let indexPath = indexPaths.first {
            guard
                let dataSourceItem = dataSource.itemIdentifier(for: indexPath)
            else {
                return
            }

            switch dataSourceItem {
            case .listenNowEpisode(let podcastEpisode, _),
                 .recentlyPlayedEpisode(let podcastEpisode, _):
                onPodcastEpisodeCellSelected(podcastEpisode.itemID)
            }
        }
    }
}

// MARK: - Layout Composition
extension FeedListenDashboardViewController {

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


    func makeFeedContentSectionLayout(
        itemHeight: CGFloat
    ) -> NSCollectionLayoutSection {
        
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = itemContentInsets

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(192.0),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)

        section.orthogonalScrollingBehavior = .continuous
        section.boundarySupplementaryItems = [makeSectionHeader()]
        section.contentInsets = .init(top: 5, leading: 0, bottom: 5, trailing: 0)

        return section
    }


    func makeSectionProvider() -> NSCollectionViewCompositionalLayoutSectionProvider {
        { (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            guard
                let section = CollectionViewSection(rawValue: sectionIndex)
            else {
                preconditionFailure("Unexpected Section index path")
            }
            
            switch section {
            case .recentlyReleasePods:
                return self.makeFeedContentSectionLayout(itemHeight: 300.0)
            case .recentlyPlayedPods:
                return self.makeFeedContentSectionLayout(itemHeight: 300.0)
            }
        }
    }


    func makeLayout() -> NSCollectionViewLayout {
        let layoutConfiguration = NSCollectionViewCompositionalLayoutConfiguration()

        layoutConfiguration.interSectionSpacing = interSectionSpacing

        let layout = NSCollectionViewCompositionalLayout(
            sectionProvider: makeSectionProvider()
        )

        layout.configuration = layoutConfiguration

        return layout
    }
}

// MARK: - Data Source Configuration
extension FeedListenDashboardViewController {

    func makeDataSource(for collectionView: NSCollectionView) -> DataSource {
        let dataSource = DataSource(
            collectionView: collectionView,
            itemProvider: makeCellProvider()
        )

        dataSource.supplementaryViewProvider = { (collectionView, kind, indexPath) in
            if kind == NSCollectionView.elementKindSectionHeader {
                guard let headerView = collectionView.makeSupplementaryView(
                    ofKind: kind,
                    withIdentifier: NSUserInterfaceItemIdentifier("FeedSectionHeaderView"),
                    for: indexPath
                ) as? (NSView & NSCollectionViewElement) else {
                    return nil
                }
                
                guard let section = CollectionViewSection(rawValue: indexPath.section) else {
                    return nil
                }
                
                (headerView as? FeedSectionHeaderView)?.renderWith(title: section.titleForDisplay)
                
                return headerView
            }
            return nil
        }

        return dataSource
    }


    func configureDataSource(for collectionView: NSCollectionView) {
        dataSource = makeDataSource(for: collectionView)

        let snapshot = makeSnapshotForCurrentState()

        dataSource.apply(snapshot, animatingDifferences: false)
    }


    func makeSnapshotForCurrentState() -> DataSourceSnapshot {
        var snapshot = DataSourceSnapshot()

        // Handle recently released (subscribed) podcasts
        let recentlyReleasedEpisodes = followedPodcastFeeds
            .compactMap { $0.episodesArray.first }
            .map { episode in
                DataSourceItem.listenNowEpisode(episode, episode.currentTime ?? 0)
            }

        snapshot.appendSections([CollectionViewSection.recentlyReleasePods])
        snapshot.appendItems(recentlyReleasedEpisodes, toSection: .recentlyReleasePods)

        // Handle recently played episodes
        let recentlyPlayedEpisodes = allPodcastFeeds
            .filter { $0.dateLastConsumed != nil }
            .compactMap { feed -> DataSourceItem? in
                guard let lastPlayedEpisode = feed.getCurrentEpisode() else { return nil }
                return DataSourceItem.recentlyPlayedEpisode(lastPlayedEpisode, lastPlayedEpisode.currentTime ?? 0)
            }

        if !recentlyPlayedEpisodes.isEmpty {
            snapshot.appendSections([CollectionViewSection.recentlyPlayedPods])
            snapshot.appendItems(recentlyPlayedEpisodes, toSection: .recentlyPlayedPods)
        }

        return snapshot
    }


    func updateWithNew(
        podcastFeeds: [PodcastFeed],
        shouldAnimate: Bool = true
    ) {
        for feed in podcastFeeds {
            let _ = feed.episodesArray
        }
        
        self.followedPodcastFeeds = podcastFeeds.filter { $0.subscribed || $0.chat != nil }.sorted { (first, second) in
            let firstDate = first.getLastEpisode()?.datePublished ?? Date.init(timeIntervalSince1970: 0)
            let secondDate = second.getLastEpisode()?.datePublished ?? Date.init(timeIntervalSince1970: 0)
            
            return firstDate > secondDate
        }
        
        self.allPodcastFeeds = podcastFeeds.sorted { (first: PodcastFeed, second: PodcastFeed) in
            let firstDate = first.dateLastConsumed ?? Date.init(timeIntervalSince1970: 0)
            let secondDate = second.dateLastConsumed ?? Date.init(timeIntervalSince1970: 0)
            
            if (firstDate == secondDate) {
                let firstDate = first.episodesArray.first?.datePublished ?? Date.init(timeIntervalSince1970: 0)
                let secondDate = second.episodesArray.first?.datePublished ?? Date.init(timeIntervalSince1970: 0)

                return firstDate > secondDate
            }

            return firstDate > secondDate
        }

        let snapshot = makeSnapshotForCurrentState()
        
        dataSource.apply(snapshot, animatingDifferences: false) {
            DispatchQueue.main.async {
                for subview in self.feedCollectionView.subviews {
                    if let scrollView = subview as? NSScrollView {
                        scrollView.drawsBackground = false
                        scrollView.backgroundColor = .clear
                        scrollView.contentView.backgroundColor = .clear
                    }
                }
            }
        }
    }


    func fetchItems() {
        do {
            try fetchedResultsController.performFetch()
        } catch {
            AlertHelper.showAlert(
                title: "Data Loading Error",
                message: "\(error)"
            )
        }
    }
}

// MARK: - Data Source View Providers
extension FeedListenDashboardViewController {

    func makeCellProvider() -> DataSource.ItemProvider {
        { [weak self] (collectionView, indexPath, dataSourceItem) -> NSCollectionViewItem? in
            guard let _ = self else {
                return nil
            }
            
            guard let cell = collectionView.makeItem(
                withIdentifier: NSUserInterfaceItemIdentifier(
                    rawValue: CollectionViewCell.reuseID
                ),
                for: indexPath
            ) as? CollectionViewCell else {
                return nil
            }

            switch dataSourceItem {
            case .listenNowEpisode(let podcastEpisode, _):
                cell.configure(withItem: podcastEpisode, section: CollectionViewSection.recentlyReleasePods.rawValue)
            case .recentlyPlayedEpisode(let podcastEpisode, _):
                cell.configure(withItem: podcastEpisode, section: CollectionViewSection.recentlyPlayedPods.rawValue)
            }

            return cell
        }
    }
}

extension FeedListenDashboardViewController {

    static func makeFetchedResultsController(
        using managedObjectContext: NSManagedObjectContext
    ) -> NSFetchedResultsController<ContentFeed> {
        let fetchRequest = ContentFeed.FetchRequests.podcastFeeds()

        return NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: managedObjectContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }
}

// MARK: - `NSFetchedResultsControllerDelegate` Methods
extension FeedListenDashboardViewController: NSFetchedResultsControllerDelegate {

    /// Called when the contents of the fetched results controller change.
    ///
    /// If this method is implemented, no other delegate methods will be invoked.
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        guard
            let resultController = controller as? NSFetchedResultsController<NSManagedObject>,
            let firstSection = resultController.sections?.first,
            let foundFeeds = firstSection.objects as? [ContentFeed]
        else {
            return
        }
        
        let podcastFeeds = foundFeeds.map {
            PodcastFeed.convertFrom(contentFeed: $0)
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateWithNew(
                podcastFeeds: podcastFeeds
            )
            
//            self?.onNewResultsFetched(podcastFeeds.count)
        }
    }
}

// MARK: - Layout & Data Structure
extension FeedListenDashboardViewController {

    enum CollectionViewSection: Int, CaseIterable {

        /// New episodes
        case recentlyReleasePods

        /// Podcasts that the user is subscribed to
        case recentlyPlayedPods


        var titleForDisplay: String {
            switch self {
            case .recentlyReleasePods:
                return "feed.recently-released".localized
            case .recentlyPlayedPods:
                return "recently.played".localized
            }
        }
    }


    enum DataSourceItem: Hashable, Equatable {
        case listenNowEpisode(PodcastEpisode, Int)
        case recentlyPlayedEpisode(PodcastEpisode, Int)
        
        static func == (lhs: DataSourceItem, rhs: DataSourceItem) -> Bool {
            if let lhsEpisode = lhs.episodeEntity,
               let rhsEpisode = rhs.episodeEntity {
                    
                return
                    lhsEpisode.0.itemID == rhsEpisode.0.itemID &&
                    lhsEpisode.0.title == rhsEpisode.0.title &&
                    lhsEpisode.1 == rhsEpisode.1
            }

            return false
         }

        func hash(into hasher: inout Hasher) {
            if let episode = self.episodeEntity {
                hasher.combine(episode.0.itemID)
                hasher.combine(episode.0.title)
                hasher.combine(episode.1)
            }
        }
    }


    typealias ReusableHeaderView = FeedSectionHeaderView
    typealias CollectionViewCell = FeedListenCollectionViewItem
    typealias CellDataItem = DataSourceItem
    typealias DataSource = NSCollectionViewDiffableDataSource<CollectionViewSection, CellDataItem>
    typealias DataSourceSnapshot = NSDiffableDataSourceSnapshot<CollectionViewSection, CellDataItem>
}

extension FeedListenDashboardViewController.DataSourceItem {
    
    var episodeEntity: (PodcastEpisode, Int)? {
        switch self {
        case .listenNowEpisode(let podcastEpisode, let currentTime),
             .recentlyPlayedEpisode(let podcastEpisode, let currentTime):
            return (podcastEpisode, currentTime)
        }
    }
}

extension FeedListenCollectionViewItem {
    static let reuseID = "FeedListenCollectionViewItem"
    static let nib: NSNib? = {
        NSNib(nibNamed: "FeedListenCollectionViewItem", bundle: nil)
    }()
}
