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
    @objc optional func shouldGoToDashboard()
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
    let som = SphinxOnionManager.sharedInstance
    
    var signupMode: SignupHelper.SignupMode = .NewUser
    var viewMode: WelcomeViewMode = .Connecting
    
    var isNewUser: Bool {
        get {
            return signupMode == .NewUser
        }
    }
    
    var subView: NSView? = nil
    var doneCompletion: ((String?) -> ())? = nil
    
    var selfContactFetchListener: NSFetchedResultsController<UserContact>?
    var timeoutTimer: Timer?
    
    static func instantiate(
        signupMode: SignupHelper.SignupMode,
        viewMode: WelcomeViewMode
    ) -> WelcomeEmptyViewController {
        let viewController = StoryboardScene.Signup.welcomeEmptyViewController.instantiate()
        viewController.signupMode = signupMode
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
            listenForSelfContactRegistration()
            setupTimeoutTimer()
        }
    }
    
    func shouldGoBack() {
        messageBubbleHelper.showGenericMessageView(text: "generic.error.message".localized)
        
        resetUserData()
        
        DelayPerformedHelper.performAfterDelay(seconds: 1.5, completion: { [weak self] in
            guard let self = self else {
                return
            }
            self.view.window?.replaceContentBy(vc: WelcomeCodeViewController.instantiate(mode: self.signupMode))
        })
    }
    
    func resetUserData() {
        som.disconnectMqtt()
        
        SphinxOnionManager.resetSharedInstance()
        ContactsService.sharedInstance.reset()
        UserData.sharedInstance.clearData()
        SphinxCache().removeAll()
    }
}

extension WelcomeEmptyViewController : WelcomeEmptyViewDelegate {
    func shouldContinueTo(mode: Int) {
        let welcomeViewMode = WelcomeViewMode(rawValue: mode)
        
        switch (welcomeViewMode) {
        case .Welcome:
            view.window?.replaceContentBy(vc: WelcomeEmptyViewController.instantiate(signupMode: self.signupMode, viewMode: welcomeViewMode!))
            return
        case .FriendMessage:
            view.window?.replaceContentBy(vc: WelcomeEmptyViewController.instantiate(signupMode: self.signupMode, viewMode: welcomeViewMode!))
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
    
    func shouldGoToDashboard() {
        presentDashboard()
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
    
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        if let resultController = controller as? NSFetchedResultsController<NSManagedObject>,
           let firstSection = resultController.sections?.first {
            
            if let _ = firstSection.objects?.first {
                selfContactFetchListener = nil
                
                timeoutTimer?.invalidate()
                timeoutTimer = nil
                
                finalizeSignup()
            }
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
            } else {
                self.finalizeSignup()
            }
        }
    }
    
    private func finalizeSignup() {
        if let contact = som.pendingContact, contact.isOwner == true {
            som.isV2InitialSetup = true
            
            SignupHelper.step = SignupHelper.SignupStep.OwnerCreated.rawValue
            
            if isNewUser {
                shouldContinueTo(mode: WelcomeViewMode.FriendMessage.rawValue)
            } else {
                shouldContinueTo(mode: -1)
            }
        } else {
            shouldGoBack()
        }
    }
}
