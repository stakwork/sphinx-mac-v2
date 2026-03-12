//
//  LsatListViewController.swift
//  Sphinx
//

import Foundation
import Cocoa

class LsatListViewController: NSViewController {

    var lsatList: [LSat] = []

    // Collection view + scroll view, created programmatically
    var scrollView: NSScrollView!
    var collectionView: NSCollectionView!

    lazy var viewModel: LsatListViewModel = {
        return LsatListViewModel(vc: self)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        viewModel.setupWith(lsatList: lsatList, collectionView: collectionView)
    }

    private func setupCollectionView() {
        // Scroll view filling entire VC view
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Flow layout
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = false

        scrollView.documentView = collectionView
    }

    static func instantiate(lsatList: [LSat]) -> LsatListViewController {
        let viewController = StoryboardScene.Dashboard.lsatListViewController.instantiate()
        viewController.lsatList = lsatList
        return viewController
    }
}
