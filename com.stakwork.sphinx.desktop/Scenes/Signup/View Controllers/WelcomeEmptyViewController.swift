//
//  WelcomeEmptyViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 11/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa
import SwiftyJSON

@objc protocol WelcomeEmptyViewDelegate: AnyObject {
    @objc optional func shouldContinueTo(mode: Int)
}

class WelcomeEmptyViewController: WelcomeErrorHandlerViewController {
    
    @IBOutlet weak var viewContainer: NSView!
    
    public enum WelcomeViewMode: Int {
        case Connecting
        case Welcome
        case FriendMessage
    }
    
    let userData = UserData.sharedInstance
    let contactsService = ContactsService()
    
    var mode: SignupHelper.SignupMode = .NewUser
    var continueMode: WelcomeViewMode? = .Connecting
    var viewMode: WelcomeViewMode = .Connecting
    
    var isNewUser: Bool {
        get {
            return mode == .NewUser
        }
    }
    
    var subView: NSView? = nil
    var doneCompletion: ((String?) -> ())? = nil
    
    var selfContactFetchListener: NSFetchedResultsController<UserContact>?
    var timeoutTimer: Timer?
    
    static func instantiate(
        mode: SignupHelper.SignupMode,
        viewMode: WelcomeViewMode
    ) -> WelcomeEmptyViewController {
        let viewController = StoryboardScene.Signup.welcomeEmptyViewController.instantiate()
        viewController.mode = mode
        viewController.viewMode = viewMode
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadViewForMode()
        continueProcess()
    }
    
    func loadViewForMode() {
        switch (viewMode) {
        case .Connecting:
            subView = ConnectingView(frame: NSRect.zero, delegate: self)
        case .Welcome:
            subView = WelcomeView(frame: NSRect.zero, delegate: self)
        case .FriendMessage:
            subView = FriendMessageView(frame: NSRect.zero, delegate: self)
        }
        
        self.view.addSubview(subView!)
        subView!.constraintTo(view: self.view)
    }
    
    func continueProcess() {
        if viewMode == .Connecting {
            if isNewUser {
                continueSignup()
            } else {
                continueRestore()
            }
        }
    }
    
    func continueRestore() {
        listenForSelfContactRegistration()
        setupTimeoutTimer()
    }
    
    func continueSignup() {
        listenForSelfContactRegistration()
        setupTimeoutTimer()
    }
    
    func shouldGoBackToWelcome() {
        messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized)
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.5, completion: {
            self.view.window?.replaceContentBy(vc: WelcomeCodeViewController.instantiate(mode: .ExistingUser))
        })
    }
    
    func shouldGoBack() {
        messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized)
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.5, completion: {
            self.view.window?.replaceContentBy(vc: WelcomeCodeViewController.instantiate(mode: .NewUser))
        })
    }
}

extension WelcomeEmptyViewController : WelcomeEmptyViewDelegate {
    func shouldContinueTo(mode: Int) {
        let mode = WelcomeViewMode(rawValue: mode)
        continueMode = mode
        
        switch (mode) {
        case .Welcome:
            view.window?.replaceContentBy(vc: WelcomeEmptyViewController.instantiate(mode: .ExistingUser, viewMode: mode!))
            return
        case .FriendMessage:
            view.window?.replaceContentBy(vc: WelcomeEmptyViewController.instantiate(mode: .NewUser, viewMode: mode!))
            return
        default:
            break
        }

        if isNewUser {
            view.window?.replaceContentBy(
                vc: WelcomeLightningViewController.instantiate()
            )
        } else {
            view.window?.replaceContentBy(
                vc: WelcomeLightningViewController.instantiate(mode: .NamePin, signupMode: .ExistingUser)
            )
        }
    }
    
    func closeWindow() {
        self.view.window?.close()
    }
}

extension WelcomeEmptyViewController : NSFetchedResultsControllerDelegate {
    private func listenForSelfContactRegistration() {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext

        let fetchRequest: NSFetchRequest<UserContact> = UserContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isOwner == true AND routeHint != nil")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "index", ascending: true)]
        
        selfContactFetchListener = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: managedContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        selfContactFetchListener?.delegate = self

        do {
            try selfContactFetchListener?.performFetch()
        } catch _ as NSError {
            timeoutTimer?.invalidate()
            selfContactFetchListener = nil
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let _ = controller.fetchedObjects?.first {
            selfContactFetchListener = nil
            
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            
            finalizeSignup()
        }
    }
    
    private func setupTimeoutTimer() {
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            if self.selfContactFetchListener?.fetchedObjects?.first == nil {
                DispatchQueue.main.async {
                    self.timeoutTimer?.invalidate()
                    self.timeoutTimer = nil

                    self.shouldGoBack()
                }
            }
        }
    }
    
    private func finalizeSignup() {
        let som = SphinxOnionManager.sharedInstance
        
        if let contact = som.pendingContact, contact.isOwner == true {
            som.isV2InitialSetup = true
            
            SignupHelper.step = SignupHelper.SignupStep.OwnerCreated.rawValue
            
            self.shouldContinueTo(mode: WelcomeViewMode.FriendMessage.rawValue)
        } else {
            shouldGoBack()
        }
    }
}
