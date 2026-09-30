//
//  NetworkMonitor.swift
//  sphinx
//
//  Created by James Carucci on 6/10/24.
//  Copyright © 2024 sphinx. All rights reserved.
//
import Foundation
import Network
import Cocoa

class NetworkMonitor: @unchecked Sendable {
    nonisolated(unsafe) static let shared = NetworkMonitor()
    private var nwMonitor: NWPathMonitor?
    private var isNwMonitoring = false

    /// Guards `isConnected` / `hasReceivedPath`. Written from the `NWMonitor`
    /// background queue and read from the main thread (bolt icon, banner gate).
    private let stateLock = NSLock()

    private var _isConnected: Bool = false
    private(set) var isConnected: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isConnected
        }
        set {
            stateLock.lock()
            _isConnected = newValue
            stateLock.unlock()
        }
    }

    /// True once at least one real `NWPath` update has been delivered since
    /// the monitor last started (including the seeded first callback on iOS
    /// parity paths). Reset on `stopMonitoring()`.
    private var _hasReceivedPath: Bool = false
    private var hasReceivedPath: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _hasReceivedPath
        }
        set {
            stateLock.lock()
            _hasReceivedPath = newValue
            stateLock.unlock()
        }
    }

    var connectionType: NWInterface.InterfaceType?
    
    private init() {}

    // This method should be called first to start monitoring the network connection.
    func startMonitoring() {
        if isNwMonitoring { return }
        
        nwMonitor = NWPathMonitor()
        
        // Network changes have to be monitored on the background as the changes are to be continuously monitored
        let queue = DispatchQueue(label: "NWMonitor")
        nwMonitor?.start(queue: queue)
        nwMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.updateConnectionStatus(path: path)
        }
        isNwMonitoring = true
    }

    // Call this method to stop the monitoring.
    func stopMonitoring() {
        if isNwMonitoring, let monitor = nwMonitor {
            monitor.cancel()
            self.nwMonitor = nil
            isNwMonitoring = false
        }
        hasReceivedPath = false
    }

    // Use SCNetworkReachability to determine the actual network state
    private func updateConnectionStatus(path: NWPath) {
        isConnected = path.status == .satisfied
        hasReceivedPath = true
        
        // Determine the connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = nil // Connection type is unknown
        }

        // Example Notification Logic
        if isConnected {
            NotificationCenter.default.post(name: .connectedToInternet, object: nil)
        } else {
            NotificationCenter.default.post(name: .disconnectedFromInternet, object: nil)
        }
    }

    func isNetworkConnected() -> Bool {
        guard let _ = nwMonitor else { return false }
        return isConnected
    }

    /// UI-facing reachability reading. Fails **open** (treats "no path update
    /// yet" as reachable) so the bolt/banner don't flash orange/hidden during
    /// the brief window before the monitor's first callback. Once a real path
    /// update has landed, this mirrors `isConnected` exactly.
    var isReachableOrUnknown: Bool {
        !hasReceivedPath || isConnected
    }
}
