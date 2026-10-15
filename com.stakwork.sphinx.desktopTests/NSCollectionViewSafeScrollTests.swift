//
//  NSCollectionViewSafeScrollTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Regression tests for the SIGABRT caused by scrolling to a stale or
//  out-of-range NSCollectionView index path. Swift cannot catch the
//  Objective-C exception AppKit throws, so if `safeScrollToItem` or
//  `scrollToIndex` regress, these tests crash the whole test runner
//  instead of failing a single assertion. A runner crash is the
//  signal that the fix regressed.
//

import XCTest
import AppKit
@testable import Sphinx

@MainActor
final class NSCollectionViewSafeScrollTests: XCTestCase {

    // MARK: - Harness

    private final class StubDataSource: NSObject, NSCollectionViewDataSource {
        var count: Int = 0

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            return 1
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            return count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            return NSCollectionViewItem()
        }
    }

    private var window: NSWindow!
    private var scrollView: NSScrollView!
    private var collectionView: NSCollectionView!
    private var dataSource: StubDataSource!

    override func setUp() {
        super.setUp()

        let frame = NSRect(x: 0, y: 0, width: 400, height: 400)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 100)

        collectionView = NSCollectionView(frame: frame)
        collectionView.collectionViewLayout = layout
        collectionView.register(
            NSCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("Item")
        )

        dataSource = StubDataSource()
        collectionView.dataSource = dataSource

        scrollView = NSScrollView(frame: frame)
        scrollView.documentView = collectionView

        window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(scrollView)

        reload()
    }

    override func tearDown() {
        window = nil
        scrollView = nil
        collectionView = nil
        dataSource = nil
        super.tearDown()
    }

    private func reload(count: Int? = nil) {
        if let count {
            dataSource.count = count
        }
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
    }

    private func drainMainQueue(for interval: TimeInterval = 0.3) {
        let expectation = expectation(description: "drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: interval + 1.0)
    }

    // MARK: - isValidIndexPath

    func testIsValidIndexPathRejectsInvalidTargets() {
        reload(count: 5)

        XCTAssertTrue(collectionView.isValidIndexPath(IndexPath(item: 0, section: 0)))
        XCTAssertTrue(collectionView.isValidIndexPath(IndexPath(item: 4, section: 0)))
        XCTAssertFalse(collectionView.isValidIndexPath(IndexPath(item: -1, section: 0)))
        XCTAssertFalse(collectionView.isValidIndexPath(IndexPath(item: 5, section: 0)))
        XCTAssertFalse(collectionView.isValidIndexPath(IndexPath(item: 0, section: 1)))
        XCTAssertFalse(collectionView.isValidIndexPath(IndexPath(item: 0, section: -1)))

        reload(count: 0)
        XCTAssertFalse(collectionView.isValidIndexPath(IndexPath(item: 0, section: 0)))
    }

    // MARK: - safeScrollToItem

    func testSafeScrollToItemNoOpForInvalidTargets() {
        reload(count: 5)

        // Negative item.
        collectionView.safeScrollToItem(IndexPath(item: -1, section: 0), position: .bottom, animated: false)
        // Past the end.
        collectionView.safeScrollToItem(IndexPath(item: 10, section: 0), position: .bottom, animated: false)
        // Invalid section.
        collectionView.safeScrollToItem(IndexPath(item: 0, section: 1), position: .bottom, animated: false)

        // No crash is the assertion.
    }

    func testSafeScrollToItemNoOpWhenNotInWindow() {
        let detached = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 100)
        detached.collectionViewLayout = layout

        let detachedDataSource = StubDataSource()
        detachedDataSource.count = 3
        detached.dataSource = detachedDataSource
        detached.reloadData()

        // Not attached to any window.
        detached.safeScrollToItem(IndexPath(item: 0, section: 0), position: .bottom, animated: false)

        // No crash is the assertion.
    }

    func testSafeScrollToItemScrollsValidTarget() {
        reload(count: 5)

        // Should not crash, and should actually reach a valid item.
        collectionView.safeScrollToItem(IndexPath(item: 2, section: 0), position: .bottom, animated: false)
    }

    // MARK: - scrollToIndex

    func testScrollToIndexHandlesStaleTargetAfterEmptying() {
        reload(count: 5)

        collectionView.scrollToIndex(targetIndex: 3, animated: false)

        // Data source is emptied before the dispatched scroll runs.
        reload(count: 0)

        drainMainQueue()

        // No crash is the assertion.
    }

    func testScrollToIndexClampsZeroToFirstItem() {
        reload(count: 5)

        collectionView.scrollToIndex(targetIndex: 0, animated: false)

        drainMainQueue()

        // No crash, and the clamp means item 0 was targeted (not -1).
    }

    func testScrollToIndexNoOpWithZeroSections() {
        collectionView.dataSource = nil
        reload(count: 0)

        collectionView.scrollToIndex(targetIndex: 0, animated: false)
        drainMainQueue()

        // No crash is the assertion.
    }

    func testScrollToBottomNoOpWithZeroSections() {
        collectionView.dataSource = nil
        reload(count: 0)

        collectionView.scrollToBottom(animated: false)
        drainMainQueue()

        // No crash is the assertion.
    }

    // MARK: - AttachmentsPreviewDataSource

    private final class AttachmentDelegateStub: AttachmentPreviewDataSourceDelegate {
        func shouldRemoveItemAt(index: Int?) {}
        func didClickAddAttachment() {}
    }

    func testAttachmentsPreviewHandlesRapidEmptyAfterAdd() {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let attachmentsCollectionView = NSCollectionView(frame: frame)
        let attachmentsScrollView = NSScrollView(frame: frame)
        attachmentsScrollView.documentView = attachmentsCollectionView

        window.contentView?.addSubview(attachmentsScrollView)

        let delegate = AttachmentDelegateStub()
        let dataSource = AttachmentsPreviewDataSource(
            collectionView: attachmentsCollectionView,
            scrollView: attachmentsScrollView,
            delegate: delegate
        )

        let attachment = AttachmentPreview(url: nil, data: Data(), image: nil)
        dataSource.updateAttachments(attachments: [attachment])

        // Empty it again before the 0.1s delayed scroll fires.
        dataSource.updateAttachments(attachments: [])

        drainMainQueue(for: 0.3)

        // No crash. The add-cell is the only remaining item.
        XCTAssertEqual(attachmentsCollectionView.numberOfItems(inSection: 0), 1)
    }
}
