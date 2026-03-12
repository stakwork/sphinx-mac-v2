//
//  LsatListViewModel.swift
//  Sphinx
//
//  Created by James Carucci on 5/2/23.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Foundation
import Cocoa


class LsatListViewModel: NSObject {
    var vc: LsatListViewController
    var tableView: NSTableView
    var lsatList: [LSat] = []
    
    init(vc: LsatListViewController, tableView: NSTableView) {
        self.vc = vc
        self.tableView = tableView
        tableView.register(NSNib(nibNamed: "LsatListTableCellView", bundle: nil), forIdentifier: NSUserInterfaceItemIdentifier(rawValue: "LsatListTableCellView"))
    }
    
    func setupTableView(lsatsList: [LSat]) {
        tableView.delegate = self
        tableView.dataSource = self
        self.lsatList = lsatsList
        tableView.tableColumns.first?.identifier = NSUserInterfaceItemIdentifier(rawValue: "LsatListTableCellView")
        tableView.reloadData()
    }
}

extension LsatListViewModel: NSTableViewDelegate, NSTableViewDataSource {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 120.0
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "LsatListTableCellView"), owner: self) as? LsatListTableCellView else { return nil }
        cell.configureWith(lsat: lsatList[row], index: row)
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        print(tableColumn)
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return lsatList.count
    }
    
    func numberOfColumns(in tableView: NSTableView) -> Int {
        return 1
    }
}

extension LsatListViewModel: LsatListCellDelegate {
    func copyToken(index: Int) {
        let lsat = lsatList[index]
        let token = "\(lsat.macaroon):\(lsat.preimage ?? "")"
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
            let formatter = ISO8601DateFormatter()
            dict["createdAt"] = formatter.string(from: createdAt)
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                ClipboardHelper.copyToClipboard(text: jsonString)
            }
        } catch {
            NewMessageBubbleHelper().showGenericMessageView(text: "Error copying L402 JSON data. Please try again.", in: nil)
        }
    }
}
