//
//  WelcomeInitialViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

class WelcomeInitialViewController: NSViewController {
    
    @IBOutlet weak var leftContainer: NSView!
    @IBOutlet weak var rightContainer: NSView!
    @IBOutlet weak var newUserView: SignupButtonView!
    @IBOutlet weak var existingUserView: SignupButtonView!
    
    enum Buttons: Int {
        case NewUser
        case ExistingUser
    }
    
    static func instantiate() -> WelcomeInitialViewController {
        let viewController = StoryboardScene.Signup.welcomeInitialViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        leftContainer.alphaValue = 0.0
        rightContainer.alphaValue = 0.0
        
        newUserView.configureWith(title: "new.user".localized, icon: "", tag: Buttons.NewUser.rawValue, delegate: self)
        existingUserView.configureWith(title: "existing.user".localized, icon: "", tag: Buttons.ExistingUser.rawValue, delegate: self)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.leftContainer.alphaValue = 1.0
            self.rightContainer.alphaValue = 1.0
        })
    }
}

extension WelcomeInitialViewController : SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        let mode = (tag == Buttons.NewUser.rawValue) ? SignupHelper.SignupMode.NewUser : SignupHelper.SignupMode.ExistingUser
        view.window?.replaceContentBy(vc: WelcomeCodeViewController.instantiate(mode: mode))
    }
}
