//
//  TimezoneSharingView.swift
//  Sphinx
//
//  Created by Bryant MacMahon on 3/11/25.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

//
//  TimezoneSharingView.swift
//  Sphinx
//
//  Created by Bryant MacMahon on 3/11/25.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

 protocol PickerViewDelegate: AnyObject {
     func didSelectValue(value: String)
 }

protocol TimezoneSharingViewDelegate: AnyObject {
    func shouldPresentPickerViewWith(delegate: PickerViewDelegate)
}

class TimezoneSharingView: NSView, LoadableNib {
    
    weak var delegate: TimezoneSharingViewDelegate?

    @IBOutlet var contentView: NSView!
    @IBOutlet weak var shareTimezoneSwitchButton: CustomButton!
    @IBOutlet weak var shareTimezoneSwitchContainer: NSBox!
    @IBOutlet weak var shareTimezoneSwitchCircle: NSBox!
    @IBOutlet weak var timezoneField: NSTextField!
    
    public static let kDefaultValue = "Use Computer Settings"
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
    }
    
    func configureView() {
        shareTimezoneSwitchContainer.wantsLayer = true
        shareTimezoneSwitchCircle.wantsLayer = true
        shareTimezoneSwitchContainer.layer?.cornerRadius = shareTimezoneSwitchContainer.frame.size.height / 2
        shareTimezoneSwitchCircle.layer?.cornerRadius = shareTimezoneSwitchCircle.frame.size.height / 2
    }
    
    
//    func setup() {
//        timezoneField.stringValue = TimezoneSharingView.kDefaultValue
//    }
//    
//    @IBAction func timezoneButtonTouched(_ sender: Any) {
//        delegate?.shouldPresentPickerViewWith(delegate: self)
//    }
    
  

}

//extension TimezoneSharingView: PickerViewDelegate {
//    func didSelectValue(value: String) {
//        timezoneField.stringValue = value
//    }
//}

