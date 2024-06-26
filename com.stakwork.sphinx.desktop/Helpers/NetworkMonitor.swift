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
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)

    var isConnected: Bool = false
    var connectionType: NWInterface.InterfaceType?

    private init() {}

    func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            self.isConnected = path.status == .satisfied
            self.connectionType = self.getConnectionType(path)

            if self.isConnected  == false{
                NotificationCenter.default.post(name: .connectedToInternet, object: nil)
            } else {
                NotificationCenter.default.post(name: .disconnectedFromInternet, object: nil)
            }
        }
        monitor.start(queue: queue)
    }

    private func getConnectionType(_ path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return nil
        }
    }

    deinit {
        monitor.cancel()
    }
}

