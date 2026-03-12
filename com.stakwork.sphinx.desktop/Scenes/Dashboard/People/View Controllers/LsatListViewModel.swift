//
//  LsatListViewModel.swift
//  Sphinx
//

import Foundation
import Cocoa

class LsatListViewModel: NSObject {

    weak var vc: LsatListViewController?
    var collectionView: NSCollectionView?
    var lsatList: [LSat] = []

    let kItemHeight: CGFloat = 110.0

    init(vc: LsatListViewController) {
        self.vc = vc
    }

    func setupWith(lsatList: [LSat], collectionView: NSCollectionView) {
        self.collectionView = collectionView
        // Sort: active first, then by createdAt descending
        self.lsatList = lsatList.sorted {
            let aActive = $0.status == LSat.LSatStatus.active.rawValue
            let bActive = $1.status == LSat.LSatStatus.active.rawValue
            if aActive != bActive { return aActive }
            let aDate = $0.createdAt ?? Date.distantPast
            let bDate = $1.createdAt ?? Date.distantPast
            return aDate > bDate
        }

        collectionView.registerItem(LsatListCollectionViewItem.self)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.reloadData()
    }
}

extension LsatListViewModel: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return lsatList.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier("LsatListCollectionViewItem"),
            for: indexPath
        ) as! LsatListCollectionViewItem
        item.configureWith(lsat: lsatList[indexPath.item], index: indexPath.item)
        item.delegate = self
        return item
    }
}

extension LsatListViewModel: NSCollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        return NSSize(width: collectionView.frame.width, height: kItemHeight)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int
    ) -> CGFloat {
        return 0
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int
    ) -> CGFloat {
        return 0
    }
}

extension LsatListViewModel: LsatListCellDelegate {
    func copyToken(index: Int) {
        let lsat = lsatList[index]
        let token = "LSAT \(lsat.macaroon):\(lsat.preimage ?? "")"
        ClipboardHelper.copyToClipboard(text: token)
    }

    func copyJSON(index: Int) {
        let lsat = lsatList[index]

        var dict: [String: Any] = [
            "identifier": lsat.identifier,
            "macaroon": lsat.macaroon,
            "paymentRequest": lsat.paymentRequest,
            "status": lsat.status
        ]
        if let preimage = lsat.preimage { dict["preimage"] = preimage }
        if let issuer = lsat.issuer { dict["issuer"] = issuer }
        if let paths = lsat.paths { dict["paths"] = paths }
        if let metadata = lsat.metadata { dict["metadata"] = metadata }
        if let createdAt = lsat.createdAt {
            dict["createdAt"] = ISO8601DateFormatter().string(from: createdAt)
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                ClipboardHelper.copyToClipboard(text: jsonString)
            }
        } catch {
            NewMessageBubbleHelper().showGenericMessageView(text: "Error copying L402 JSON. Please try again.", in: nil)
        }
    }
}
