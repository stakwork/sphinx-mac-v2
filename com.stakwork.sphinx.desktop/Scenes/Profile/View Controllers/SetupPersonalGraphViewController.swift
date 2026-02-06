//
//  SetupPersonalGraphViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 10/11/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Cocoa

class SetupPersonalGraphViewController: NSViewController {

    @IBOutlet weak var graphLabelField: SignupFieldView!
    @IBOutlet weak var repoUrlField: SignupFieldView!
    @IBOutlet weak var githubTokenField: SignupFieldView!
    @IBOutlet weak var selectPathButton: SignupButtonView!
    @IBOutlet weak var pathLabel: NSTextField!
    @IBOutlet weak var cloneRepoButton: SignupButtonView!
    @IBOutlet weak var installTaskButton: SignupButtonView!
    @IBOutlet weak var setupGraphButton: SignupButtonView!
    @IBOutlet weak var startGraphButton: SignupButtonView!
    @IBOutlet weak var stopGraphButton: SignupButtonView!

    let userData = UserData.sharedInstance
    let personalGraphManager = PersonalGraphManager.sharedInstance

    var newMessageBubbleHelper = NewMessageBubbleHelper()

    var selectedPath: String? = nil

    // Track graph running state
    var isGraphRunning: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "personalGraphRunning")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "personalGraphRunning")
        }
    }

    // Track if task is installed
    var isTaskInstalled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "personalGraphTaskInstalled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "personalGraphTaskInstalled")
        }
    }

    // Loading indicator views (created programmatically)
    var loadingContainerView: NSView?
    var loadingWheel: NSProgressIndicator?
    var loadingLabel: NSTextField?
    var loadingTextView: NSTextView?
    var loadingScrollView: NSScrollView?

    public enum Fields: Int {
        case GraphLabel
        case RepoUrl
        case GithubToken
    }

    public enum ButtonTags: Int {
        case SelectPath = 0
        case CloneRepo = 1
        case InstallTask = 2
        case SetupGraph = 3
        case StartGraph = 4
        case StopGraph = 5
    }

    static func instantiate() -> SetupPersonalGraphViewController {
        let viewController = StoryboardScene.Profile.setupPersonalGraphViewController.instantiate()
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureView()
    }

    func configureView() {
        // Graph Label Field
        graphLabelField.configureWith(
            placeHolder: "Graph Label",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "Graph Label",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.GraphLabel.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphLabel),
            validationType: .alphanumericWithSpaces(maxLength: 12),
            delegate: self
        )

        // GitHub Repo URL Field
        repoUrlField.configureWith(
            placeHolder: "GitHub Repo URL",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "GitHub Repo URL",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.RepoUrl.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.githubRepoUrl),
            delegate: self
        )

        // GitHub Token Field
        githubTokenField.configureWith(
            placeHolder: "GitHub Token (optional)",
            placeHolderColor: NSColor.Sphinx.SecondaryText,
            label: "GitHub Token",
            textColor: NSColor.white,
            backgroundColor: NSColor(hex: "#101317"),
            field: Fields.GithubToken.rawValue,
            value: userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.githubToken),
            delegate: self
        )

        // Select Path Button
        selectPathButton.configureWith(
            title: "SELECT PATH TO CLONE",
            icon: "",
            tag: ButtonTags.SelectPath.rawValue,
            delegate: self
        )

        // Path Label
        selectedPath = userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.repoLocalPath)
        updatePathLabel()

        // Clone Repo Button
        cloneRepoButton.configureWith(
            title: "CLONE REPO",
            icon: "",
            tag: ButtonTags.CloneRepo.rawValue,
            delegate: self
        )

        // Install Task Button
        installTaskButton.configureWith(
            title: "INSTALL TASK",
            icon: "",
            tag: ButtonTags.InstallTask.rawValue,
            delegate: self
        )

        // Setup Graph Button
        setupGraphButton.configureWith(
            title: "SET UP GRAPH",
            icon: "",
            tag: ButtonTags.SetupGraph.rawValue,
            delegate: self
        )

        // Start Graph Button
        startGraphButton.configureWith(
            title: "START GRAPH",
            icon: "",
            tag: ButtonTags.StartGraph.rawValue,
            delegate: self
        )

        // Stop Graph Button
        stopGraphButton.configureWith(
            title: "STOP GRAPH",
            icon: "",
            tag: ButtonTags.StopGraph.rawValue,
            delegate: self
        )

        updateButtonStates()
    }

    func updatePathLabel() {
        if let path = selectedPath, !path.isEmpty {
            pathLabel.stringValue = path
            pathLabel.textColor = NSColor.white
        } else {
            pathLabel.stringValue = "No path selected"
            pathLabel.textColor = NSColor.Sphinx.SecondaryText
        }
    }

    func updateButtonStates() {
        let hasPath = selectedPath != nil && !selectedPath!.isEmpty
        let hasRepoUrl = !repoUrlField.getFieldValue().isEmpty
        let repoCloned = isRepoCloned()
        let taskInstalled = isTaskInstalled

        // Clone Repo: enabled when repo URL and path are set, but repo not yet cloned
        cloneRepoButton.buttonDisabled = !hasPath || !hasRepoUrl || repoCloned

        // Install Task: enabled after repo is cloned, but task not yet installed
        installTaskButton.buttonDisabled = !repoCloned || taskInstalled

        // If repo not cloned or task not installed: setup/start/stop buttons disabled
        if !repoCloned || !taskInstalled {
            setupGraphButton.buttonDisabled = true
            startGraphButton.buttonDisabled = true
            stopGraphButton.buttonDisabled = true
        } else if isGraphRunning {
            // Graph is running: only STOP enabled
            setupGraphButton.buttonDisabled = true
            startGraphButton.buttonDisabled = true
            stopGraphButton.buttonDisabled = false
        } else {
            // Task installed but graph not running: SETUP and START enabled, STOP disabled
            setupGraphButton.buttonDisabled = false
            startGraphButton.buttonDisabled = !isGraphSetup() // Only enable if was set up before
            stopGraphButton.buttonDisabled = true
        }
    }

    /// Checks if the repository has been cloned by verifying if the path contains a .git folder
    func isRepoCloned() -> Bool {
        guard let path = selectedPath, !path.isEmpty else {
            print("[PersonalGraph] isRepoCloned: No path selected")
            return false
        }

        let gitPath = (path as NSString).appendingPathComponent(".git")
        let exists = FileManager.default.fileExists(atPath: gitPath)
        print("[PersonalGraph] isRepoCloned: Checking \(gitPath) - exists: \(exists)")
        return exists
    }

    /// Checks if the graph has been set up by verifying if the .env file exists
    func isGraphSetup() -> Bool {
        guard let path = selectedPath, !path.isEmpty else {
            return false
        }

        let envPath = (path as NSString).appendingPathComponent("localstack/swarm/.env")
        return FileManager.default.fileExists(atPath: envPath)
    }

    func saveValues() {
        let graphLabel = graphLabelField.getFieldValue()
        let repoUrl = repoUrlField.getFieldValue()
        let githubToken = githubTokenField.getFieldValue()

        if graphLabel.isNotEmpty {
            userData.save(personalGraphValue: graphLabel, for: KeychainManager.KeychainKeys.personalGraphLabel)
        }

        if repoUrl.isNotEmpty {
            userData.save(personalGraphValue: repoUrl, for: KeychainManager.KeychainKeys.githubRepoUrl)
        }

        if githubToken.isNotEmpty {
            userData.save(personalGraphValue: githubToken, for: KeychainManager.KeychainKeys.githubToken)
        }

        if let path = selectedPath, !path.isEmpty {
            userData.save(personalGraphValue: path, for: KeychainManager.KeychainKeys.repoLocalPath)
        }
    }

    func showError(_ message: String) {
        newMessageBubbleHelper.showGenericMessageView(
            text: message,
            delay: 3,
            textColor: NSColor.white,
            backColor: NSColor.Sphinx.BadgeRed,
            backAlpha: 1.0
        )
    }

    func showSuccess(_ message: String) {
        newMessageBubbleHelper.showGenericMessageView(
            text: message,
            delay: 3,
            textColor: NSColor.white,
            backColor: NSColor.Sphinx.PrimaryGreen,
            backAlpha: 1.0
        )
    }

    // MARK: - Loading Indicator

    func showLoading(text: String, withProgress: Bool = false) {
        hideLoading()

        // Create container view
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.9).cgColor
        container.layer?.cornerRadius = 8
        view.addSubview(container)

        // Create header view for wheel and label
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerView)

        // Create loading wheel
        let wheel = NSProgressIndicator()
        wheel.translatesAutoresizingMaskIntoConstraints = false
        wheel.style = .spinning
        wheel.controlSize = .small
        wheel.startAnimation(nil)
        headerView.addSubview(wheel)

        // Create label
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = NSColor.white
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.alignment = .left
        headerView.addSubview(label)

        // Base constraints
        var constraints: [NSLayoutConstraint] = [
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 350),

            headerView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 24),

            wheel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            wheel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: wheel.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ]

        if withProgress {
            // Create scroll view for output
            let scrollView = NSScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.backgroundColor = NSColor.clear
            scrollView.drawsBackground = false
            container.addSubview(scrollView)

            // Create text view
            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
            textView.textColor = NSColor.green
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainer?.containerSize = NSSize(width: 310, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.autoresizingMask = [.width]

            scrollView.documentView = textView

            constraints.append(contentsOf: [
                container.heightAnchor.constraint(equalToConstant: 300),

                scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
            ])

            loadingTextView = textView
            loadingScrollView = scrollView
        } else {
            constraints.append(container.heightAnchor.constraint(equalToConstant: 56))
            constraints.append(headerView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16))
        }

        NSLayoutConstraint.activate(constraints)

        loadingContainerView = container
        loadingWheel = wheel
        loadingLabel = label
    }

    func updateLoadingText(_ text: String) {
        loadingLabel?.stringValue = text
    }

    func appendLoadingOutput(_ text: String) {
        guard let textView = loadingTextView else { return }

        textView.textStorage?.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.green,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ]
        ))

        // Auto-scroll to bottom
        textView.scrollToEndOfDocument(nil)
    }

    func hideLoading() {
        loadingWheel?.stopAnimation(nil)
        loadingContainerView?.removeFromSuperview()
        loadingContainerView = nil
        loadingWheel = nil
        loadingLabel = nil
        loadingTextView = nil
        loadingScrollView = nil
    }
}

// MARK: - Button Actions
extension SetupPersonalGraphViewController: SignupButtonViewDelegate {
    func didClickButton(tag: Int) {
        guard let buttonTag = ButtonTags(rawValue: tag) else { return }

        switch buttonTag {
        case .SelectPath:
            selectPathAction()
        case .CloneRepo:
            cloneRepoAction()
        case .InstallTask:
            installTaskAction()
        case .SetupGraph:
            setupGraphAction()
        case .StartGraph:
            startGraphAction()
        case .StopGraph:
            stopGraphAction()
        }
    }

    func selectPathAction() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Select folder to clone repository"
        openPanel.prompt = "Select"

        openPanel.beginSheetModal(for: self.view.window!) { [weak self] response in
            guard let self = self else { return }

            if response == .OK, let url = openPanel.url {
                self.selectedPath = url.path
                self.updatePathLabel()
                self.updateButtonStates()
                self.saveValues()
            }
        }
    }

    func cloneRepoAction() {
        guard let path = selectedPath, !path.isEmpty else {
            showError("Please select a path first")
            return
        }

        let repoUrl = repoUrlField.getFieldValue()
        guard !repoUrl.isEmpty else {
            showError("Please enter a GitHub repo URL")
            return
        }

        let githubToken = githubTokenField.getFieldValue()

        // Save values before starting
        saveValues()

        // Show loading state
        cloneRepoButton.buttonDisabled = true
        showLoading(text: "Cloning repository...")

        print("[PersonalGraph] Cloning to path: \(path)")

        personalGraphManager.cloneRepo(
            repoUrl: repoUrl,
            token: githubToken.isEmpty ? nil : githubToken,
            localPath: path
        ) { [weak self] result in
            guard let self = self else { return }

            self.hideLoading()

            switch result {
            case .success(let output):
                print("[PersonalGraph] Clone success. Output: \(output)")
                self.showSuccess("Repository cloned successfully!")
                self.updateButtonStates()
            case .failure(let error):
                print("[PersonalGraph] Clone failed: \(error.localizedDescription)")
                self.cloneRepoButton.buttonDisabled = false
                self.showError("Clone failed: \(error.localizedDescription)")
            }
        }
    }

    func installTaskAction() {
        guard let path = selectedPath, !path.isEmpty else {
            showError("Please select a path first")
            return
        }

        // Show loading state with progress output
        installTaskButton.buttonDisabled = true
        showLoading(text: "Installing task...", withProgress: true)

        personalGraphManager.installTask(
            atPath: path,
            progressHandler: { [weak self] output in
                self?.appendLoadingOutput(output)
            }
        ) { [weak self] result in
            guard let self = self else { return }

            self.hideLoading()

            switch result {
            case .success(_):
                self.isTaskInstalled = true
                self.updateButtonStates()
                self.showSuccess("Task installed successfully!")
            case .failure(let error):
                self.updateButtonStates()
                self.showError("Failed to install task: \(error.localizedDescription)")
            }
        }
    }

    func setupGraphAction() {
        guard let path = selectedPath, !path.isEmpty else {
            showError("Please select a path first")
            return
        }

        // Show confirmation alert since this is destructive
        let alert = NSAlert()
        alert.messageText = "Setup Graph?"
        alert.informativeText = "This will reset all containers and delete all data. Are you sure you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Setup")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        // Save values before starting
        saveValues()

        // Show loading state with progress output
        setupGraphButton.buttonDisabled = true
        showLoading(text: "Running task fresh...", withProgress: true)

        personalGraphManager.runTaskFresh(
            atPath: path,
            progressHandler: { [weak self] output in
                self?.appendLoadingOutput(output)
            }
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(_):
                // Extract and save the token
                self.updateLoadingText("Extracting token...")

                self.personalGraphManager.extractAndSaveNodeToken(fromRepoPath: path) { tokenResult in
                    self.hideLoading()

                    // Mark graph as running after successful setup
                    self.isGraphRunning = true

                    switch tokenResult {
                    case .success:
                        self.showSuccess("Graph setup completed and running!")
                        self.updateButtonStates()
                    case .failure(let error):
                        self.showError("Setup completed but token extraction failed: \(error.localizedDescription)")
                        self.updateButtonStates()
                    }
                }
            case .failure(let error):
                self.hideLoading()
                self.updateButtonStates()
                self.showError("Task fresh failed: \(error.localizedDescription)")
            }
        }
    }

    func startGraphAction() {
        guard let path = selectedPath, !path.isEmpty else {
            showError("Please select a path first")
            return
        }

        startGraphButton.buttonDisabled = true
        showLoading(text: "Starting graph...", withProgress: true)

        personalGraphManager.runTaskUp(
            atPath: path,
            progressHandler: { [weak self] output in
                self?.appendLoadingOutput(output)
            }
        ) { [weak self] result in
            guard let self = self else { return }

            self.hideLoading()

            switch result {
            case .success(_):
                self.isGraphRunning = true
                self.updateButtonStates()
                self.showSuccess("Graph started successfully!")
            case .failure(let error):
                self.updateButtonStates()
                self.showError("Failed to start graph: \(error.localizedDescription)")
            }
        }
    }

    func stopGraphAction() {
        guard let path = selectedPath, !path.isEmpty else {
            showError("Please select a path first")
            return
        }

        stopGraphButton.buttonDisabled = true
        showLoading(text: "Stopping graph...", withProgress: true)

        personalGraphManager.runTaskDown(
            atPath: path,
            progressHandler: { [weak self] output in
                self?.appendLoadingOutput(output)
            }
        ) { [weak self] result in
            guard let self = self else { return }

            self.hideLoading()

            switch result {
            case .success(_):
                self.isGraphRunning = false
                self.updateButtonStates()
                self.showSuccess("Graph stopped successfully!")
            case .failure(let error):
                self.updateButtonStates()
                self.showError("Failed to stop graph: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Field Delegate
extension SetupPersonalGraphViewController: SignupFieldViewDelegate {
    func didChangeText(text: String) {
        updateButtonStates()
    }

    func didUseTab(field: Int) {
        DispatchQueue.main.async {
            let field = Fields(rawValue: field)
            switch field {
            case .GraphLabel:
                self.view.window?.makeFirstResponder(self.repoUrlField.getTextField())
            case .RepoUrl:
                self.view.window?.makeFirstResponder(self.githubTokenField.getTextField())
            default:
                self.view.window?.makeFirstResponder(self.graphLabelField.getTextField())
            }
        }
    }
}
