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

class NetworkMonitor {
    static let shared = NetworkMonitor()
    private var nwMonitor: NWPathMonitor?
    private var isNwMonitoring = false
    
    private(set) var isConnected: Bool = false
    var connectionType: NWInterface.InterfaceType?
    var firstRun : Bool = true
    
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
    }

    // Use SCNetworkReachability to determine the actual network state
    private func updateConnectionStatus(path: NWPath) {
        if(firstRun){//compensate for iOS quirks!
            isConnected = path.status == .satisfied
            firstRun = false
        }
        else{
            isConnected = path.status != .satisfied
        }
        
        
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

        print("Network status changed - isConnected: \(isConnected), Connection Type: \(String(describing: connectionType))")

        // Example Notification Logic
        if isConnected {
            NotificationCenter.default.post(name: .connectedToInternet, object: nil)
        } else {
            NotificationCenter.default.post(name: .disconnectedFromInternet, object: nil)
        }
    }

    func checkConnectionSync() -> Bool {
        guard let monitor = nwMonitor else { return false }
        return isConnected
    }
}

