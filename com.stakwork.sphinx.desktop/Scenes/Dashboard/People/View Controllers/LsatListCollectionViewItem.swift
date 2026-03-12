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
        cardBox.cornerRadius = 12
        cardBox.borderWidth = 0

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
        button.layer?.borderWidth = 0.8
        button.layer?.borderColor = NSColor.Sphinx.PrimaryBlue.cgColor
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.cursor = .pointingHand

        let title = button.title
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Roboto-Bold", size: 10) ?? NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.Sphinx.PrimaryBlue,
            .paragraphStyle: {
                let ps = NSMutableParagraphStyle()
                ps.alignment = .center
                return ps
            }()
        ]
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    func configureWith(lsat: LSat, index: Int) {
        self.itemIndex = index

        tokenLabel.stringValue = lsat.macaroon
        tokenLabel.cell?.lineBreakMode = .byTruncatingTail

        issuerLabel.stringValue = (lsat.issuer ?? "").components(separatedBy: ":").first ?? ""

        let isActive = lsat.status == LSat.LSatStatus.active.rawValue
        // NSStackView with detachesHiddenViews=YES will auto-collapse the pill
        activePillBox.isHidden = !isActive

        createdAtLabel.stringValue = lsat.createdAt?.getStringDate(format: "MMM dd, yyyy · h:mm a") ?? ""
    }

    @IBAction func handleCopyToken(_ sender: Any) {
        delegate?.copyToken(index: itemIndex)
    }

    @IBAction func handleCopyJSON(_ sender: Any) {
        delegate?.copyJSON(index: itemIndex)
    }
}
