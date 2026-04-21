//
//  WebGameViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/08/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

@MainActor protocol WebAppViewControllerDelegate: AnyObject {
    func webAppDidTapBackToChat()
    func webAppDidTapOpenInWindow(chat: Chat?, appURL: String?, isAppURL: Bool)
}

class WebAppViewController: NSViewController {
    
    @IBOutlet weak var authorizeModalContainer: NSView!
    @IBOutlet weak var authorizeAppView: AuthorizeAppView!
    @IBOutlet weak var authorizeAppViewHeight: NSLayoutConstraint!
    @IBOutlet weak var loadingView: NSImageView!
    @IBOutlet weak var loadingIndicator: NSProgressIndicator!
    @IBOutlet weak var personalGraphLabelContainer: NSBox!
    @IBOutlet weak var personalGraphLabel: NSTextField!
    
    var headerBarView: NSView!
    var urlLabel: NSTextField!
    var refreshButton: CustomButton!
    var backToChatButton: CustomButton!
    var openInWindowButton: CustomButton!
    var rightButtonsStack: NSStackView!
    
    /// Set to true once this VC is handed to a separate NSWindow so the "open in window" button hides
    var isOpenedInWindow: Bool = false {
        didSet {
            openInWindowButton?.isHidden = isOpenedInWindow
        }
    }
    
    weak var webAppDelegate: WebAppViewControllerDelegate?
    
    var webView: WKWebView!
    var appURL: String! = nil
    var chat: Chat? = nil
    var finishLoadingTimer : Timer? = nil
    var isPersonalGraph: Bool = false
    
    let webAppHelper = WebAppHelper()
    
    let userData = UserData.sharedInstance
    
    static func instantiate(
        chat: Chat? = nil,
        appURL: String! = nil,
        isAppURL: Bool = true,
        isPersonalGraph: Bool = false
    ) -> WebAppViewController? {
        let viewController = StoryboardScene.Dashboard.webAppViewController.instantiate()
        
        viewController.chat = chat
        viewController.isPersonalGraph = isPersonalGraph
        
        if let appURL = appURL {
            viewController.appURL = appURL
        } else if let tribeInfo = chat?.tribeInfo, let appUrl = isAppURL ? tribeInfo.appUrl : tribeInfo.secondBrainUrl, !appUrl.isEmpty {
            viewController.appURL = appUrl
        }
        
        return viewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webAppHelper.delegate = self
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        
        authorizeModalContainer.isHidden = true
        authorizeModalContainer.alphaValue = 0.0
        
        personalGraphLabelContainer.fillColor = NSColor.Sphinx.Body
        
        setupHeaderBar()
    }
    
    func setupHeaderBar() {
        // Container
        headerBarView = NSView()
        headerBarView.translatesAutoresizingMaskIntoConstraints = false
        headerBarView.wantsLayer = true
        headerBarView.layer?.backgroundColor = NSColor.Sphinx.HeaderBG.cgColor
        view.addSubview(headerBarView)
        NSLayoutConstraint.activate([
            headerBarView.topAnchor.constraint(equalTo: view.topAnchor),
            headerBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBarView.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Bottom separator
        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.Sphinx.SecondaryText.withAlphaComponent(0.2).cgColor
        headerBarView.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: headerBarView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: headerBarView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: headerBarView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])

        // URL label
        urlLabel = NSTextField(labelWithString: "")
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.textColor = NSColor.Sphinx.SecondaryText
        urlLabel.font = NSFont.systemFont(ofSize: 12)
        urlLabel.lineBreakMode = .byTruncatingTail
        urlLabel.maximumNumberOfLines = 1
        urlLabel.isEditable = false
        urlLabel.isSelectable = false
        urlLabel.isBordered = false
        urlLabel.backgroundColor = .clear
        headerBarView.addSubview(urlLabel)

        // Refresh button
        refreshButton = CustomButton()
        refreshButton.cursor = .pointingHand
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        refreshButton.contentTintColor = NSColor.Sphinx.SecondaryText
        refreshButton.isBordered = false
        refreshButton.bezelStyle = .shadowlessSquare
        refreshButton.imagePosition = .imageOnly
        refreshButton.imageScaling = .scaleProportionallyUpOrDown
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked(_:))
        refreshButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        refreshButton.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Back to chat button
        backToChatButton = CustomButton()
        backToChatButton.cursor = .pointingHand
        let backConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        backToChatButton.image = NSImage(systemSymbolName: "bubble.left", accessibilityDescription: nil)?.withSymbolConfiguration(backConfig)
        backToChatButton.contentTintColor = NSColor.Sphinx.SecondaryText
        backToChatButton.isBordered = false
        backToChatButton.bezelStyle = .shadowlessSquare
        backToChatButton.imagePosition = .imageOnly
        backToChatButton.imageScaling = .scaleProportionallyUpOrDown
        backToChatButton.target = self
        backToChatButton.action = #selector(backToChatButtonClicked(_:))
        backToChatButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        backToChatButton.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Open in window button
        openInWindowButton = CustomButton()
        openInWindowButton.cursor = .pointingHand
        openInWindowButton.image = NSImage(named: "openNewWindow")
        openInWindowButton.contentTintColor = NSColor.Sphinx.SecondaryText
        openInWindowButton.isBordered = false
        openInWindowButton.bezelStyle = .shadowlessSquare
        openInWindowButton.imagePosition = .imageOnly
        openInWindowButton.imageScaling = .scaleProportionallyUpOrDown
        openInWindowButton.target = self
        openInWindowButton.action = #selector(openInWindowButtonClicked(_:))
        openInWindowButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        openInWindowButton.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Stack the three buttons horizontally — hiding a button collapses its space automatically
        rightButtonsStack = NSStackView(views: [refreshButton, backToChatButton, openInWindowButton])
        rightButtonsStack.orientation = .horizontal
        rightButtonsStack.spacing = 8
        rightButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        headerBarView.addSubview(rightButtonsStack)

        NSLayoutConstraint.activate([
            // URL label anchored to left, trailing to stack
            urlLabel.leadingAnchor.constraint(equalTo: headerBarView.leadingAnchor, constant: 12),
            urlLabel.trailingAnchor.constraint(equalTo: rightButtonsStack.leadingAnchor, constant: -8),
            urlLabel.centerYAnchor.constraint(equalTo: headerBarView.centerYAnchor),

            // Stack pinned to right edge
            rightButtonsStack.trailingAnchor.constraint(equalTo: headerBarView.trailingAnchor, constant: -8),
            rightButtonsStack.centerYAnchor.constraint(equalTo: headerBarView.centerYAnchor),
        ])

        headerBarView.isHidden = true
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // Only register as window delegate when running in a separate window.
        // In inline mode we don't want windowWillClose to fire and call teardown().
        if isOpenedInWindow {
            view.window?.delegate = self
        }
        
        addAndLoadWebView()
    }
    
    func resizeSubviews(frame: NSRect) {
        view.frame = frame
        // webView is constrained programmatically, no manual frame needed
    }
    
    func addAndLoadWebView(forceReload: Bool = false) {
        var didChangeAppUrl = false
        let personalGraphUrl = userData.getPersonalGraphUrl()
        
        if isPersonalGraph {
            didChangeAppUrl = self.appURL != personalGraphUrl
        }
        self.appURL = isPersonalGraph ? personalGraphUrl : self.appURL
        
        let appUrlNotSet = (appURL == nil || appURL.isEmpty)
        let shouldShowPersonalGraphLabel = isPersonalGraph && appUrlNotSet
        personalGraphLabelContainer.isHidden = !shouldShowPersonalGraphLabel
        loadingIndicator.isHidden = true
        
        guard let appURL = appURL, !appURL.isEmpty else {
            webView?.isHidden = true
            headerBarView.isHidden = true
            toggleAuthorizationView(show: false)
            return
        }
        if webView != nil {
            if didChangeAppUrl || forceReload {
                webView?.isHidden = false
                headerBarView.isHidden = false
                urlLabel.stringValue = appURL
                loadPage()
            }
            return
        }
        addWebView()
        headerBarView.isHidden = false
        urlLabel.stringValue = appURL
        loadPage()
    }
    
    func addWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(webAppHelper, name: webAppHelper.messageHandler)
        configuration.preferences.setValue(true, forKey: "fullScreenEnabled")
        
        let rect = CGRect(x: 0, y: 0, width: 700, height: 500)
        webView = WKWebView(frame: rect, configuration: configuration)
        webView.customUserAgent = "Sphinx"
        webView.isHidden = true
        webView.navigationDelegate = self
        
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        
        webView.setBackgroundColor(color: NSColor.clear)
        addLoadingView()
        finishLoadingTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkForWebViewDoneLoading), userInfo: nil, repeats: true)

        self.view.addSubview(webView, positioned: .below, relativeTo: authorizeModalContainer)
        addWebViewConstraints()

        webAppHelper.setWebView(webView, authorizeHandler: configureAuthorizeView, authorizeBudgetHandler: configureBudgetView)
    }
    
    func addLoadingView(){
        loadingView.isHidden = false
        loadingIndicator.isHidden = false
        loadingView.image = #imageLiteral(resourceName: "whiteIcon")
        loadingIndicator.startAnimation(self)
    }
    
    func removeLoadingView(){
        loadingView.isHidden = true
        loadingIndicator.isHidden = true
    }
    
    @objc func checkForWebViewDoneLoading(){
        if(webView.isLoading == false){
            finishLoadingTimer?.invalidate()
            webView.isHidden = false
            removeLoadingView()
        }
    }
    
    func configureAuthorizeView(_ dict: [String: AnyObject]) {
        let viewHeight = authorizeAppView.configureFor(url: appURL, delegate: self, dict: dict, showBudgetField: false)
        authorizeAppViewHeight.constant = viewHeight
        authorizeAppView.layoutSubtreeIfNeeded()
        toggleAuthorizationView(show: true)
    }
    
    func configureBudgetView(_ dict: [String: AnyObject]) {
        let viewHeight = authorizeAppView.configureFor(url: appURL, delegate: self, dict: dict, showBudgetField: true)
        authorizeAppViewHeight.constant = viewHeight
        authorizeAppView.layoutSubtreeIfNeeded()
        toggleAuthorizationView(show: true)
    }
    
    func addWebViewConstraints() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: headerBarView!, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1.0, constant: 0.0).isActive = true
    }
    
    func loadPage() {
        var url: String = appURL
        
        if let tribeUUID = chat?.tribeInfo?.uuid ?? chat?.uuid {
            url = url.withURLParam(key: "uuid", value: tribeUUID)
        }
        
        if let host = chat?.host {
            url = url.withURLParam(key: "host", value: host)
        }
        
        if let url = URL(string: url) {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
            webView.load(request)
        }
    }
    
    @IBAction func refreshButtonClicked(_ sender: Any) {
        addAndLoadWebView(forceReload: true)
    }

    @objc func backToChatButtonClicked(_ sender: Any) {
        webAppDelegate?.webAppDidTapBackToChat()
    }

    @objc func openInWindowButtonClicked(_ sender: Any) {
        webAppDelegate?.webAppDidTapOpenInWindow(chat: chat, appURL: appURL, isAppURL: !isPersonalGraph)
    }

    func teardown() {
        finishLoadingTimer?.invalidate()
        finishLoadingTimer = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: webAppHelper.messageHandler)
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
    }
}

extension WebAppViewController : WKNavigationDelegate {
     func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
         if navigationAction.navigationType == .linkActivated  {
             if let url = navigationAction.request.url, url.absoluteString.contains("open=system") {
                 NSWorkspace.shared.open(url)
                 decisionHandler(.cancel)
                 return
             } else {
                 decisionHandler(.allow)
                 return
             }
         } else {
             decisionHandler(.allow)
             return
         }
     }
 }

extension WebAppViewController : AuthorizeAppViewDelegate {
    func shouldCloseAuthorizeView() {
        toggleAuthorizationView(show: false)
    }
    
    func toggleAuthorizationView(show: Bool) {
        if show {
            authorizeModalContainer.isHidden = false
        }
        
        AnimationHelper.animateViewWith(duration: 0.3, animationsBlock: {
            self.authorizeModalContainer.alphaValue = show ? 1.0 : 0.0
        }) {
            if !show {
                self.authorizeModalContainer.isHidden = true
            }
        }
    }
    
    func shouldAuthorizeBudgetWith(amount: Int, dict: [String : AnyObject]) {
        webAppHelper.authorizeWebApp(amount: amount, dict: dict, completion: {
            self.chat?.updateWebAppLastDate()
            self.shouldCloseAuthorizeView()
        })
    }
    
    func shouldAuthorizeWith(dict: [String : AnyObject]) {
        webAppHelper.authorizeNoBudget(dict: dict, completion: {
            self.chat?.updateWebAppLastDate()
            self.shouldCloseAuthorizeView()
        })
    }
}

extension WebAppViewController : NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        teardown()
    }
}

extension WebAppViewController: WebAppHelperDelegate {
    func setBudget(budget: Int) {
        print(budget)
    }
}
