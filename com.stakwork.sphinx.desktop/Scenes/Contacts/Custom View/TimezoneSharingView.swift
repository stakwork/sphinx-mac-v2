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
    @IBOutlet weak var shareTimezoneSwitchCircleLeading: NSLayoutConstraint!
    @IBOutlet weak var timezoneField: NSTextField!
    
    public static let kDefaultValue = "Use Computer Settings"
    
    var timezoneShareEnabled = true
    
    let kSwitchOnLeading: CGFloat = 25
    let kSwitchOffLeading: CGFloat = 2
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadViewFromNib()
        
        configureView()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadViewFromNib()
        
        configureView()
    }
    
    func configureView() {
        shareTimezoneSwitchButton.cursor = .pointingHand
        
        timezoneField.stringValue = TimezoneSharingView.kDefaultValue
        
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
    }
    
    @IBAction func timezoneEnableButtonClicked(_ sender: Any) {
        timezoneShareEnabled = !timezoneShareEnabled
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
//        delegate?.shouldPresentPickerViewWith(delegate: self)
    }
    
    func toggleSharePhotoSwitch(on: Bool) {
        shareTimezoneSwitchCircleLeading.constant = on ? kSwitchOnLeading : kSwitchOffLeading
        shareTimezoneSwitchContainer.fillColor = on ? NSColor.Sphinx.PrimaryBlue : NSColor.Sphinx.MainBottomIcons
    }
}

//extension TimezoneSharingView: PickerViewDelegate {
//    func didSelectValue(value: String) {
//        timezoneField.stringValue = value
//    }
//}

