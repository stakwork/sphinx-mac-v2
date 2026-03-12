//
//  LsatListTableCellView.swift
//  Sphinx
//
//  Created by James Carucci on 5/2/23.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa

protocol LsatListCellDelegate: NSObject {
    func copyToken(index: Int)
    func copyJSON(index: Int)
}

class LsatListTableCellView: NSTableCellView {

    @IBOutlet weak var tokenLabel: NSTextField!
    @IBOutlet weak var issuerLabel: NSTextField!
    @IBOutlet weak var activePillBox: NSBox!
    @IBOutlet weak var activeLabel: NSTextField!
    @IBOutlet weak var createdAtLabel: NSTextField!
    @IBOutlet weak var copyTokenButton: CustomButton!
    @IBOutlet weak var copyJSONButton: CustomButton!

    weak var delegate: LsatListCellDelegate? = nil
    var index: Int? = nil

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    func configureWith(lsat: LSat, index: Int) {
        self.index = index

        tokenLabel.stringValue = lsat.macaroon
        tokenLabel.cell?.lineBreakMode = .byTruncatingTail

        issuerLabel.stringValue = lsat.issuer ?? ""

        let isActive = lsat.status == LSat.LSatStatus.active.rawValue
        activePillBox.isHidden = !isActive
        activePillBox.cornerRadius = 10
        activePillBox.fillColor = NSColor.Sphinx.PrimaryGreen

        createdAtLabel.stringValue = lsat.createdAt?.getStringDate(format: "MMM dd, yyyy") ?? ""
    }

    @IBAction func handleCopyToken(_ sender: Any) {
        guard let index = index else { return }
        delegate?.copyToken(index: index)
    }

    @IBAction func handleCopyJSON(_ sender: Any) {
        guard let index = index else { return }
        delegate?.copyJSON(index: index)
    }
}
