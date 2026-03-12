//
//  LsatListCollectionViewItem.swift
//  Sphinx
//

import Cocoa

protocol LsatListCellDelegate: NSObject {
    func copyToken(index: Int)
    func copyJSON(index: Int)
}

class LsatListCollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var cardBox: NSBox!
    @IBOutlet weak var tokenLabel: NSTextField!
    @IBOutlet weak var issuerLabel: NSTextField!
    @IBOutlet weak var activePillBox: NSBox!
    @IBOutlet weak var activeLabel: NSTextField!
    @IBOutlet weak var createdAtLabel: NSTextField!
    @IBOutlet weak var copyTokenButton: CustomButton!
    @IBOutlet weak var copyJSONButton: CustomButton!

    weak var delegate: LsatListCellDelegate?
    var itemIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupStyles()
    }

    private func setupStyles() {
        // Card: transparent border, system controls the fill color via named color in XIB
        cardBox.cornerRadius = 12
        cardBox.borderWidth = 0

        // Active pill styling
        activePillBox.cornerRadius = 9
        activePillBox.borderWidth = 0
        activePillBox.fillColor = NSColor.Sphinx.PrimaryGreen

        styleButton(copyTokenButton)
        styleButton(copyJSONButton)
    }

    private func styleButton(_ button: CustomButton) {
        button.wantsLayer = true
        button.isBordered = false
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1.5
        button.layer?.borderColor = NSColor.Sphinx.PrimaryBlue.cgColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.cursor = .pointingHand

        let title = button.title
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Bold", size: 11) ?? NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.Sphinx.PrimaryBlue
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    func configureWith(lsat: LSat, index: Int) {
        self.itemIndex = index

        tokenLabel.stringValue = lsat.macaroon
        tokenLabel.cell?.lineBreakMode = .byTruncatingTail

        issuerLabel.stringValue = lsat.issuer ?? ""

        let isActive = lsat.status == LSat.LSatStatus.active.rawValue
        activePillBox.isHidden = !isActive

        createdAtLabel.stringValue = lsat.createdAt?.getStringDate(format: "MMM dd, yyyy") ?? ""
    }

    @IBAction func handleCopyToken(_ sender: Any) {
        delegate?.copyToken(index: itemIndex)
    }

    @IBAction func handleCopyJSON(_ sender: Any) {
        delegate?.copyJSON(index: itemIndex)
    }
}
