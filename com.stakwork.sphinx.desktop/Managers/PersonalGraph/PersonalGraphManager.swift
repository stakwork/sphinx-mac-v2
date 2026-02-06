//
//  PersonalGraphManager.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 05/02/2026.
//  Copyright © 2026 Tomas Timinskas. All rights reserved.
//

import Foundation

class PersonalGraphManager {

    class var sharedInstance: PersonalGraphManager {
        struct Static {
            static let instance = PersonalGraphManager()
        }
        return Static.instance
    }

    let userData = UserData.sharedInstance

    // MARK: - Result Types

    enum PersonalGraphError: Error, LocalizedError {
        case invalidRepoUrl
        case invalidLocalPath
        case cloneFailed(String)
        case commandFailed(String)
        case envFileNotFound
        case tokenNotFound
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .invalidRepoUrl:
                return "Invalid repository URL"
            case .invalidLocalPath:
                return "Invalid local path"
            case .cloneFailed(let message):
                return "Clone failed: \(message)"
            case .commandFailed(let message):
                return "Command failed: \(message)"
            case .envFileNotFound:
                return "The .env file was not found at the expected location"
            case .tokenNotFound:
                return "STAKWORK_ADD_NODE_TOKEN not found in .env file"
            case .saveFailed:
                return "Failed to save token to keychain"
            }
        }
    }

    typealias CompletionHandler = (Result<String, PersonalGraphError>) -> Void
    typealias VoidCompletionHandler = (Result<Void, PersonalGraphError>) -> Void

    // MARK: - Clone Repository

    /// Clones a GitHub repository to the specified local path
    /// - Parameters:
    ///   - repoUrl: The URL of the GitHub repository (HTTPS or SSH)
    ///   - token: Optional GitHub personal access token for private repositories
    ///   - localPath: The local directory path where the repo should be cloned
    ///   - completion: Completion handler with the result (success with output or error)
    func cloneRepo(
        repoUrl: String,
        token: String?,
        localPath: String,
        completion: @escaping CompletionHandler
    ) {
        guard !repoUrl.isEmpty, repoUrl.contains("github.com") || repoUrl.hasPrefix("git@") else {
            completion(.failure(.invalidRepoUrl))
            return
        }

        guard !localPath.isEmpty else {
            completion(.failure(.invalidLocalPath))
            return
        }

        var cloneUrl = repoUrl

        // If token is provided and it's an HTTPS URL, inject the token for authentication
        if let token = token, !token.isEmpty, repoUrl.hasPrefix("https://") {
            // Convert https://github.com/user/repo.git to https://token@github.com/user/repo.git
            cloneUrl = repoUrl.replacingOccurrences(
                of: "https://",
                with: "https://\(token)@"
            )
        }

        let command = "git clone \(cloneUrl) \"\(localPath)\""

        runShellCommand(command: command, workingDirectory: nil) { result in
            switch result {
            case .success(let output):
                completion(.success(output))
            case .failure(let error):
                completion(.failure(.cloneFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - Install Task

    /// Installs the task runner by executing "sh install-task.sh" in the specified directory
    /// - Parameters:
    ///   - path: The directory path where the install script is located
    ///   - progressHandler: Optional handler for real-time output (called on main thread)
    ///   - completion: Completion handler with the result
    func installTask(
        atPath path: String,
        progressHandler: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        guard !path.isEmpty else {
            completion(.failure(.invalidLocalPath))
            return
        }

        let command = "sh install-task.sh"

        runShellCommandWithProgress(command: command, workingDirectory: path, stdinInput: nil, progressHandler: progressHandler) { result in
            switch result {
            case .success(let output):
                completion(.success(output))
            case .failure(let error):
                completion(.failure(.commandFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - Task Commands

    /// Runs "task fresh" command in the specified directory
    /// This command requires confirmation, which is auto-responded with "yes" and "DELETE EVERYTHING"
    /// - Parameters:
    ///   - path: The directory path where the command should be executed
    ///   - progressHandler: Optional handler for real-time output (called on main thread)
    ///   - completion: Completion handler with the result
    func runTaskFresh(
        atPath path: String,
        progressHandler: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        // Auto-respond to the confirmation prompts:
        // 1. First prompt expects "yes"
        // 2. Second prompt expects "DELETE EVERYTHING"
        let confirmationInput = "yes\nDELETE EVERYTHING\n"
        runTaskCommand("fresh", atPath: path, stdinInput: confirmationInput, progressHandler: progressHandler, completion: completion)
    }

    /// Runs "task up" command in the specified directory
    /// - Parameters:
    ///   - path: The directory path where the command should be executed
    ///   - progressHandler: Optional handler for real-time output (called on main thread)
    ///   - completion: Completion handler with the result
    func runTaskUp(
        atPath path: String,
        progressHandler: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        runTaskCommand("up", atPath: path, stdinInput: nil, progressHandler: progressHandler, completion: completion)
    }

    /// Runs "task down" command in the specified directory
    /// - Parameters:
    ///   - path: The directory path where the command should be executed
    ///   - progressHandler: Optional handler for real-time output (called on main thread)
    ///   - completion: Completion handler with the result
    func runTaskDown(
        atPath path: String,
        progressHandler: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        runTaskCommand("down", atPath: path, stdinInput: nil, progressHandler: progressHandler, completion: completion)
    }

    /// Generic method to run any "task" subcommand
    /// - Parameters:
    ///   - subcommand: The task subcommand (e.g., "fresh", "up", "down")
    ///   - path: The directory path where the command should be executed
    ///   - stdinInput: Optional input to send to stdin for auto-responding to prompts
    ///   - progressHandler: Optional handler for real-time output
    ///   - completion: Completion handler with the result
    private func runTaskCommand(
        _ subcommand: String,
        atPath path: String,
        stdinInput: String? = nil,
        progressHandler: ProgressHandler? = nil,
        completion: @escaping CompletionHandler
    ) {
        guard !path.isEmpty else {
            completion(.failure(.invalidLocalPath))
            return
        }

        let command = "task \(subcommand)"

        runShellCommandWithProgress(command: command, workingDirectory: path, stdinInput: stdinInput, progressHandler: progressHandler) { result in
            switch result {
            case .success(let output):
                completion(.success(output))
            case .failure(let error):
                completion(.failure(.commandFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - Extract and Save Token

    /// Extracts the STAKWORK_ADD_NODE_TOKEN from the .env file and saves it to userData
    /// - Parameters:
    ///   - repoPath: The root path of the cloned repository
    ///   - completion: Completion handler with the result
    func extractAndSaveNodeToken(
        fromRepoPath repoPath: String,
        completion: @escaping VoidCompletionHandler
    ) {
        let envFilePath = (repoPath as NSString).appendingPathComponent("localstack/swarm/.env")

        guard FileManager.default.fileExists(atPath: envFilePath) else {
            completion(.failure(.envFileNotFound))
            return
        }

        do {
            let envContents = try String(contentsOfFile: envFilePath, encoding: .utf8)

            if let token = extractTokenFromEnvContents(envContents) {
                saveNodeToken(token)
                completion(.success(()))
            } else {
                completion(.failure(.tokenNotFound))
            }
        } catch {
            completion(.failure(.envFileNotFound))
        }
    }

    /// Extracts the STAKWORK_ADD_NODE_TOKEN value from .env file contents
    /// - Parameter contents: The contents of the .env file
    /// - Returns: The token value if found, nil otherwise
    private func extractTokenFromEnvContents(_ contents: String) -> String? {
        let lines = contents.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // Look for STAKWORK_ADD_NODE_TOKEN
            if trimmedLine.hasPrefix("STAKWORK_ADD_NODE_TOKEN=") {
                let components = trimmedLine.components(separatedBy: "=")
                if components.count >= 2 {
                    // Join remaining components in case token contains "="
                    let tokenValue = components.dropFirst().joined(separator: "=")
                    // Remove quotes if present
                    let cleanedToken = tokenValue
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                    if !cleanedToken.isEmpty {
                        return cleanedToken
                    }
                }
            }
        }

        return nil
    }

    /// Saves the node token to userData using the existing personal graph storage mechanism
    /// - Parameter token: The token to save
    private func saveNodeToken(_ token: String) {
        userData.save(
            personalGraphValue: token,
            for: KeychainManager.KeychainKeys.personalGraphToken
        )
    }

    /// Retrieves the saved node token
    /// - Returns: The saved token if available
    func getNodeToken() -> String? {
        return userData.getPersonalGraphValue(with: KeychainManager.KeychainKeys.personalGraphToken)
    }

    // MARK: - Shell Command Execution

    private struct ShellError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Progress handler type for streaming output
    typealias ProgressHandler = (String) -> Void

    /// Executes a shell command asynchronously
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Optional working directory for the command
    ///   - completion: Completion handler with the result
    private func runShellCommand(
        command: String,
        workingDirectory: String?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        runShellCommandWithProgress(
            command: command,
            workingDirectory: workingDirectory,
            stdinInput: nil,
            progressHandler: nil,
            completion: completion
        )
    }

    /// Executes a shell command asynchronously with real-time progress output
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Optional working directory for the command
    ///   - stdinInput: Optional input to send to stdin (for auto-responding to prompts)
    ///   - progressHandler: Handler called with each line of output (called on main thread)
    ///   - completion: Completion handler with the result
    private func runShellCommandWithProgress(
        command: String,
        workingDirectory: String?,
        stdinInput: String? = nil,
        progressHandler: ProgressHandler?,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let inputPipe = Pipe()

            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = inputPipe
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

            // Set up environment to include common paths for tools like 'task'
            var environment = ProcessInfo.processInfo.environment
            let additionalPaths = "/usr/local/bin:/opt/homebrew/bin"
            if let existingPath = environment["PATH"] {
                environment["PATH"] = "\(additionalPaths):\(existingPath)"
            } else {
                environment["PATH"] = additionalPaths
            }
            process.environment = environment

            var fullOutput = ""
            var errorOutput = ""

            // Set up real-time output handling if progress handler is provided
            if let progressHandler = progressHandler {
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        fullOutput += str
                        DispatchQueue.main.async {
                            progressHandler(str)
                        }
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        errorOutput += str
                        DispatchQueue.main.async {
                            progressHandler(str)
                        }
                    }
                }
            }

            do {
                try process.run()

                // Send stdin input if provided (for auto-responding to prompts)
                if let stdinInput = stdinInput, let inputData = stdinInput.data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(inputData)
                    inputPipe.fileHandleForWriting.closeFile()
                }

                process.waitUntilExit()

                // Clean up handlers
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                // If no progress handler, read all output at once
                if progressHandler == nil {
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    fullOutput = String(data: outputData, encoding: .utf8) ?? ""
                    errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                }

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(fullOutput))
                    } else {
                        let errorMessage = errorOutput.isEmpty ? "Command exited with status \(process.terminationStatus)" : errorOutput
                        completion(.failure(ShellError(message: errorMessage)))
                    }
                }
            } catch {
                // Clean up handlers on error
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Convenience Methods

    /// Performs the complete setup flow: clone, run task fresh, and extract token
    /// - Parameters:
    ///   - repoUrl: The URL of the GitHub repository
    ///   - token: Optional GitHub personal access token
    ///   - localPath: The local directory path where the repo should be cloned
    ///   - progressHandler: Optional handler called with status updates
    ///   - completion: Completion handler with the final result
    func performFullSetup(
        repoUrl: String,
        token: String?,
        localPath: String,
        progressHandler: ((String) -> Void)? = nil,
        completion: @escaping VoidCompletionHandler
    ) {
        progressHandler?("Cloning repository...")

        cloneRepo(repoUrl: repoUrl, token: token, localPath: localPath) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(_):
                progressHandler?("Running task fresh...")

                self.runTaskFresh(atPath: localPath) { freshResult in
                    switch freshResult {
                    case .success(_):
                        progressHandler?("Extracting token...")

                        self.extractAndSaveNodeToken(fromRepoPath: localPath) { tokenResult in
                            switch tokenResult {
                            case .success:
                                progressHandler?("Setup complete!")
                                completion(.success(()))
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
