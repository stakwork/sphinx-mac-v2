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

class TimezoneSharingView: NSView, LoadableNib, NSComboBoxDelegate {
    
    weak var delegate: TimezoneSharingViewDelegate?

    @IBOutlet var contentView: NSView!
    @IBOutlet weak var shareTimezoneSwitchButton: CustomButton!
    @IBOutlet weak var shareTimezoneSwitchContainer: NSBox!
    @IBOutlet weak var shareTimezoneSwitchCircle: NSBox!
    @IBOutlet weak var shareTimezoneSwitchCircleLeading: NSLayoutConstraint!
    @IBOutlet weak var timezoneIdentifierComboBox: NSComboBox!
    
    public static let kDefaultValue = "Use Computer Settings"
    
    var timezoneShareEnabled = true
    
    let kSwitchOnLeading: CGFloat = 25
    let kSwitchOffLeading: CGFloat = 2
    
    var chat: Chat! = nil
    
    let newMessageBubbleHelper = NewMessageBubbleHelper()
    
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
    }
    
    func configureViewWith(chat: Chat) {
        self.chat = chat
        
        timezoneShareEnabled = chat.timezoneEnabled
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
        
        configureComboBox()
    }
    
    func configureComboBox() {
        var timezones: [String] = [TimezoneSharingView.kDefaultValue]
        timezones.append(contentsOf: TimeZone.knownTimeZoneIdentifiers)
        
        timezoneIdentifierComboBox.removeAllItems()
        timezoneIdentifierComboBox.addItems(withObjectValues: timezones)
        timezoneIdentifierComboBox.isEditable = true
        timezoneIdentifierComboBox.completes = true
        timezoneIdentifierComboBox.delegate = self
        
        if let selectedIndex = timezones.firstIndex(of: chat.timezoneIdentifier ?? TimezoneSharingView.kDefaultValue) {
            timezoneIdentifierComboBox.selectItem(at: selectedIndex)
        } else {
            timezoneIdentifierComboBox.selectItem(at: 0)
        }
    }
    
    @IBAction func timezoneEnableButtonClicked(_ sender: Any) {
        timezoneShareEnabled = !timezoneShareEnabled
        toggleSharePhotoSwitch(on: timezoneShareEnabled)
        
        let selectedValue = (timezoneIdentifierComboBox.objectValueOfSelectedItem as? String) ?? TimezoneSharingView.kDefaultValue
        
        timezoneSharingSettingsChanged(
            enabled: timezoneShareEnabled,
            identifier: (selectedValue == TimezoneSharingView.kDefaultValue ? nil : selectedValue),
            showToast: false
        )
    }
    
    func toggleSharePhotoSwitch(on: Bool) {
        shareTimezoneSwitchCircleLeading.constant = on ? kSwitchOnLeading : kSwitchOffLeading
        shareTimezoneSwitchContainer.fillColor = on ? NSColor.Sphinx.PrimaryBlue : NSColor.Sphinx.MainBottomIcons
    }
    
    func timezoneSharingSettingsChanged(
        enabled: Bool,
        identifier: String?,
        showToast: Bool = false
    ) {
        let timezoneEnabledChanged = chat.timezoneEnabled != enabled
        let timezoneIdentifierChanged = chat.timezoneIdentifier != identifier
        
        if timezoneEnabledChanged || timezoneIdentifierChanged {
            chat.timezoneEnabled = enabled
            chat.timezoneIdentifier = identifier
                
            if let pubkey = chat.ownerPubkey {
                chat.timezoneUpdated = true
                
                DataSyncManager.sharedInstance.saveTimezoneFor(
                    chatPubkey: "\(pubkey)",
                    timezone: TimezoneSetting(timezoneEnabledString: "\(enabled)", timezoneIdentifier: identifier ?? "")
                )
            }
            
            CoreDataManager.sharedManager.saveContext()
            
            if !showToast {
                return
            }
            
            newMessageBubbleHelper.showGenericMessageView(
                text: "timezone.changed".localized,
                delay: 7,
                textColor: NSColor.white,
                backColor: NSColor.Sphinx.PrimaryGreen,
                backAlpha: 1.0
            )
        }
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        valueDidChangedWith(notification)
    }
    
    func comboBoxWillDismiss(_ notification: Notification) {
        valueDidChangedWith(notification)
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        valueDidChangedWith(obj)
    }
    
    func valueDidChangedWith(_ notification: Notification) {
        let comboBox = notification.object as! NSComboBox
        if let selectedValue = comboBox.objectValueOfSelectedItem as? String {
            
            timezoneSharingSettingsChanged(
                enabled: timezoneShareEnabled,
                identifier: (selectedValue == TimezoneSharingView.kDefaultValue ? nil : selectedValue),
                showToast: true
            )
        }
    }
}

