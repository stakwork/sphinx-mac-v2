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
    func timezoneSharingSettingsChanged(enabled: Bool, identifier: String?)
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
        
        timezoneField.isEditable = false
        timezoneField.isSelectable = true
        timezoneField.stringValue = TimezoneSharingView.kDefaultValue
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(timezoneFieldClicked))
        timezoneField.addGestureRecognizer(clickGesture)
        
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
        shareTimezoneSwitchButton.target = self
        shareTimezoneSwitchButton.action = #selector(switchValueChanged)
    }

    @objc func switchValueChanged() {
        notifyDelegate()
    }

    @objc func timezoneFieldClicked() {
        if timezoneShareEnabled {
            delegate?.shouldPresentPickerViewWith(delegate: self)
        }
    }

    func configure(enabled: Bool, identifier: String?) {
        timezoneShareEnabled = enabled
        toggleSharePhotoSwitch(on: enabled)
        timezoneField.stringValue = identifier ?? TimezoneSharingView.kDefaultValue
    }

    func getTimezoneIdentifier() -> String? {
        let value = timezoneField.stringValue
        return value == TimezoneSharingView.kDefaultValue ? nil : value
    }

    func isTimezoneEnabled() -> Bool {
        return timezoneShareEnabled
    }

    private func notifyDelegate() {
        delegate?.timezoneSharingSettingsChanged(
            enabled: isTimezoneEnabled(),
            identifier: getTimezoneIdentifier()
        )
    }
    
    @IBAction func timezoneEnableButtonClicked(_ sender: Any) {
        timezoneShareEnabled = !timezoneShareEnabled
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
        
        if timezoneShareEnabled {
            delegate?.shouldPresentPickerViewWith(delegate: self)
        } else {
            timezoneField.stringValue = TimezoneSharingView.kDefaultValue
            notifyDelegate()
        }
    }
    
    func toggleSharePhotoSwitch(on: Bool) {
        shareTimezoneSwitchCircleLeading.constant = on ? kSwitchOnLeading : kSwitchOffLeading
        shareTimezoneSwitchContainer.fillColor = on ? NSColor.Sphinx.PrimaryBlue : NSColor.Sphinx.MainBottomIcons
    }
}

extension TimezoneSharingView: PickerViewDelegate {
   func didSelectValue(value: String) {
       timezoneField.stringValue = value
       notifyDelegate()
   }
}

