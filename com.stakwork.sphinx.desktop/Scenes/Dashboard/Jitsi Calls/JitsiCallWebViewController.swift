//
//  JitsiCallWebViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 07/02/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Cocoa
import WebKit
import AVFoundation

class JitsiCallWebViewController: NSViewController, WKUIDelegate, WKScriptMessageHandler {
    
    @IBOutlet weak var loadingView: NSImageView!
    @IBOutlet weak var loadingIndicator: NSProgressIndicator!
    
    var webView: WKWebView!
    var link: String! = nil
    var finishLoadingTimer : Timer? = nil
    
    static func instantiate(
        link: String
    ) -> JitsiCallWebViewController? {
        let viewController = StoryboardScene.Dashboard.jitsiCallWebViewController.instantiate()
        viewController.link = link
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        
        requestMicrophoneAccess { granted in
            if granted {
                self.addWebView()
                self.loadPage()
            } else {
                print("Microphone access denied")
                // Handle the case where microphone access is denied
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        view.window?.delegate = self
    }
    
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    func addWebView() {
        let configuration = WKWebViewConfiguration()
        
        // Configure for media playback without user interaction
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Add a content controller to handle permission requests
        let contentController = WKUserContentController()
        contentController.add(self, name: "permissionHandler")
        configuration.userContentController = contentController

        let rect = CGRect(x: 0, y: 0, width: 700, height: 500)
        webView = WKWebView(frame: rect, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Safari/605.1.15"
        webView.isHidden = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        webView.setBackgroundColor(color: NSColor.clear)
        addLoadingView()
        
        finishLoadingTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(checkForWebViewDoneLoading),
            userInfo: nil,
            repeats: true
        )

        self.view.addSubview(webView)
        addWebViewConstraints()
    }
    
    func addLoadingView(){
        loadingView.isHidden = false
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
    
    func addWebViewConstraints() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.bottom, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.bottom, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.top, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.top, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.leading, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.leading, multiplier: 1.0, constant: 0.0).isActive = true
        NSLayoutConstraint(item: self.view, attribute: NSLayoutConstraint.Attribute.trailing, relatedBy: NSLayoutConstraint.Relation.equal, toItem: webView, attribute: NSLayoutConstraint.Attribute.trailing, multiplier: 1.0, constant: 0.0).isActive = true
    }
    
    func loadPage() {
        if var link = link {
            if let owner = UserContact.getOwner(), let nickname = owner.nickname {
                if link.contains("#") {
                    link = link + "&userInfo.displayName=\"\(nickname)\"&config.prejoinConfig.enabled=false"
                } else {
                    link = link + "#userInfo.displayName=\"\(nickname)\"&config.prejoinConfig.enabled=false"
                }
            }
            
            if let url = URL(string: link) {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
                webView.load(request)
            }
        }
    }
    
    // MARK: - WKUIDelegate
    
    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        requestMicrophoneAccess { granted in
            if granted {
                decisionHandler(.grant)
            } else {
                decisionHandler(.deny)
            }
        }
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "permissionHandler" {
            // Handle any custom messages from the web content if needed
        }
    }
}

extension JitsiCallWebViewController : WKNavigationDelegate {
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

extension JitsiCallWebViewController : NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        webView.configuration.userContentController.removeAllUserScripts()
        webView.loadHTMLString("", baseURL: Bundle.main.bundleURL)
    }
}
