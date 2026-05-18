//
//  WebGameViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 18/08/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Cocoa
@preconcurrency import WebKit

class WebAppViewController: NSViewController {
    
    @IBOutlet weak var authorizeModalContainer: NSView!
    @IBOutlet weak var authorizeAppView: AuthorizeAppView!
    @IBOutlet weak var authorizeAppViewHeight: NSLayoutConstraint!
    @IBOutlet weak var loadingView: NSImageView!
    @IBOutlet weak var loadingIndicator: NSProgressIndicator!
    @IBOutlet weak var personalGraphLabelContainer: NSBox!
    @IBOutlet weak var personalGraphLabel: NSTextField!
    
    var webView: WKWebView!
    var appURL: String! = nil
    var chat: Chat? = nil
    var finishLoadingTimer : Timer? = nil
    var isPersonalGraph: Bool = false
    private var navigationDidFail = false
    
    private lazy var errorLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = NSColor.Sphinx.SecondaryText
        label.font = NSFont.systemFont(ofSize: 14)
        label.alignment = .center
        label.isHidden = true
        return label
    }()
    
    let webAppHelper = WebAppHelper()
    let logStore = WebAppLogStore()
    
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
        webAppHelper.logStore = logStore
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.Sphinx.Body.cgColor
        
        authorizeModalContainer.isHidden = true
        authorizeModalContainer.alphaValue = 0.0
        
        personalGraphLabelContainer.fillColor = NSColor.Sphinx.Body
        
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        addAndLoadWebView()
    }
    
    func resizeSubviews(frame: NSRect) {
        view.frame = frame
    }
    
    func showErrorLabel() {
        navigationDidFail = true
        finishLoadingTimer?.invalidate()
        removeLoadingView()
        webView?.isHidden = true
        errorLabel.stringValue = "Failed to load page. Use the refresh button to try again."
        errorLabel.isHidden = false
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
            toggleAuthorizationView(show: false)
            return
        }
        if webView != nil {
            if didChangeAppUrl || forceReload {
                // Only clear error state when actually reloading
                navigationDidFail = false
                errorLabel.isHidden = true
                webView?.isHidden = false
                loadPage()
            } else if navigationDidFail {
                // Re-show error state when returning to a failed webview
                webView?.isHidden = true
                errorLabel.isHidden = false
            }
            return
        }
        // First load — clear any stale error state
        navigationDidFail = false
        errorLabel.isHidden = true
        addWebView()
        loadPage()
    }
    
    func addWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(webAppHelper, name: webAppHelper.messageHandler)
        configuration.userContentController.add(self, name: "sphinxConsole")
        configuration.userContentController.add(self, name: "sphinxNetwork")
        
        let consoleScript = """
        (function() {
          function intercept(level) {
            var original = console[level];
            console[level] = function() {
              var args = Array.prototype.slice.call(arguments);
              window.webkit.messageHandlers.sphinxConsole.postMessage({ level: level, message: args.join(' ') });
              original.apply(console, arguments);
            };
          }
          ['log','warn','error','info'].forEach(intercept);
        })();
        """
        let networkScript = """
        (function() {
          var post = function(msg) {
            try { window.webkit.messageHandlers.sphinxNetwork.postMessage(msg); } catch(e) {}
          };

          // --- XMLHttpRequest ---
          var OrigXHR = window.XMLHttpRequest;
          function PatchedXHR() {
            var xhr = new OrigXHR();
            var method, url;
            var origOpen = xhr.open.bind(xhr);
            var origSend = xhr.send.bind(xhr);
            xhr.open = function(m, u) {
              method = m; url = u;
              return origOpen.apply(xhr, arguments);
            };
            xhr.send = function(body) {
              post({ type: 'xhr-start', method: method, url: url });
              xhr.addEventListener('load', function() {
                post({ type: 'xhr-done', method: method, url: url, status: xhr.status });
              });
              xhr.addEventListener('error', function() {
                post({ type: 'xhr-error', method: method, url: url });
              });
              return origSend.apply(xhr, arguments);
            };
            return xhr;
          }
          PatchedXHR.prototype = OrigXHR.prototype;
          window.XMLHttpRequest = PatchedXHR;

          // --- fetch ---
          var origFetch = window.fetch;
          window.fetch = function(input, init) {
            var method = (init && init.method) ? init.method.toUpperCase() : 'GET';
            var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : String(input);
            post({ type: 'fetch-start', method: method, url: url });
            return origFetch.apply(this, arguments).then(function(resp) {
              post({ type: 'fetch-done', method: method, url: url, status: resp.status });
              return resp;
            }).catch(function(err) {
              post({ type: 'fetch-error', method: method, url: url, error: String(err) });
              throw err;
            });
          };
        })();
        """
        let consoleUserScript = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let networkUserScript = WKUserScript(source: networkScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(consoleUserScript)
        configuration.userContentController.addUserScript(networkUserScript)
        
        configuration.preferences.setValue(true, forKey: "fullScreenEnabled")
        
        let rect = CGRect(x: 0, y: 0, width: 700, height: 500)
        webView = WKWebView(frame: rect, configuration: configuration)
        webView.customUserAgent = "Sphinx"
        webView.isHidden = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
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
        guard !navigationDidFail else {
            finishLoadingTimer?.invalidate()
            return
        }
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
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    /// Navigate the live WKWebView to a URL without replacing appURL,
    /// so WKWebView's back/forward history remains intact.
    func loadURL(_ urlString: String) {
        guard let webView = webView, let url = URL(string: urlString) else { return }
        navigationDidFail = false
        errorLabel.isHidden = true
        webView.isHidden = false
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        webView.load(request)
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

    func showLogsWindow() {
        if let existing = NSApplication.shared.windows.first(where: {
            ($0 as? TaggedWindow)?.windowIdentifier == "web-app-logs"
        }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        WindowsManager.sharedInstance.showNewWindow(
            with: "Web App Logs",
            size: CGSize(width: 700, height: 500),
            minSize: CGSize(width: 400, height: 300),
            identifier: "web-app-logs",
            styleMask: [.titled, .resizable, .closable],
            contentVC: WebAppLogsViewController.instantiate(store: logStore)
        )
    }

    /// Stops the webview and releases its resources.
    /// Called when leaving a tribe chat or when the separate window closes.
    func teardown() {
        logStore.clear()
        NSApplication.shared.windows.first(where: {
            ($0 as? TaggedWindow)?.windowIdentifier == "web-app-logs"
        })?.close()
        finishLoadingTimer?.invalidate()
        finishLoadingTimer = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sphinxConsole")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sphinxNetwork")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: webAppHelper.messageHandler)
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.removeFromSuperview()
        webView = nil
    }
}

extension WebAppViewController : WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? "unknown"
        logStore.append(.init(timestamp: Date(), level: .info, source: .navigation, message: "didStartProvisionalNavigation: \(url)"))
        NotificationCenter.default.post(name: .onWebAppNavigationChanged, object: self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? "unknown"
        logStore.append(.init(timestamp: Date(), level: .log, source: .navigation, message: "didFinish: \(url)"))
        NotificationCenter.default.post(name: .onWebAppNavigationChanged, object: self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logStore.append(.init(timestamp: Date(), level: .error, source: .navigation, message: "didFail: \(error.localizedDescription)"))
        showErrorLabel()
        NotificationCenter.default.post(name: .onWebAppNavigationChanged, object: self)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logStore.append(.init(timestamp: Date(), level: .error, source: .navigation, message: "didFailProvisionalNavigation: \(error.localizedDescription)"))
        showErrorLabel()
        NotificationCenter.default.post(name: .onWebAppNavigationChanged, object: self)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
         if navigationAction.navigationType == .linkActivated  {
             if let url = navigationAction.request.url {
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
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
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

extension WebAppViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "sphinxConsole" {
            guard let dict = message.body as? [String: Any],
                  let levelStr = dict["level"] as? String,
                  let text = dict["message"] as? String else { return }
            let level: WebAppLogStore.LogLevel
            switch levelStr {
            case "warn":  level = .warn
            case "error": level = .error
            case "info":  level = .info
            default:      level = .log
            }
            logStore.append(.init(timestamp: Date(), level: level, source: .jsConsole, message: text))

        } else if message.name == "sphinxNetwork" {
            guard let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String else { return }
            let method = dict["method"] as? String ?? "?"
            let url = dict["url"] as? String ?? "?"
            let msg: String
            let level: WebAppLogStore.LogLevel
            switch type {
            case "xhr-start", "fetch-start":
                msg = "→ \(method) \(url)"
                level = .info
            case "xhr-done", "fetch-done":
                let status = dict["status"] as? Int ?? 0
                msg = "← \(method) \(url) [\(status)]"
                level = status >= 400 ? .warn : .log
            case "xhr-error", "fetch-error":
                let err = dict["error"] as? String ?? ""
                msg = "✗ \(method) \(url)\(err.isEmpty ? "" : " – \(err)")"
                level = .error
            default:
                return
            }
            logStore.append(.init(timestamp: Date(), level: level, source: .network, message: msg))
        }
    }
}
