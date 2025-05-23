//
//  SphinxOnionManager+InvitesExtension.swift
//  sphinx
//
//  Created by James Carucci on 2/27/24.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Foundation

extension SphinxOnionManager{//invites related
    
    func messageIdIsFromHashed(msgId: Int) -> Bool {
        return msgId < 0
    }
    
    func uniqueIntHashFromString(stringInput:String) -> Int{
        return -1 * Int(Int32(stringInput.hashValue & 0x7FFFFFFF))
    }
    
    func requestInviteCode(amountMsat: Int) -> (Bool, String?) {
        guard let seed = getAccountSeed(),
              let selfContact = UserContact.getOwner(),
              let nickname = selfContact.nickname,
              let pubkey = selfContact.publicKey,
              let routeHint = selfContact.routeHint else
        {
            return (false, nil)
        }
        
        do {
            let rr = try makeInvite(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                host: "\(serverIP):\(serverPORT)",
                amtMsat: UInt64(amountMsat),
                myAlias: nickname,
                tribeHost: tribesServerIP,
                tribePubkey: defaultTribePubkey,
                inviterPubkey: pubkey,
                inviterRouteHint: routeHint
            )
            
            let _ = handleRunReturn(rr: rr)
            return (true, nil)
        } catch let error {
            return (false, (error as? SphinxError).debugDescription)
        }
    }
    
    func redeemInvite(
        inviteCode: String
    ) -> String? {
        do {
            let parsedInvite = try parseInvite(inviteQr: inviteCode)
            
            if let lsp = parsedInvite.lspHost {
                self.saveIPAndPortFrom(lspHost: lsp)
            }
            
            self.stashedInviteCode = parsedInvite.code
            
            if let contactInfo = parsedInvite.inviterContactInfo {
                self.stashedContactInfo = contactInfo
            }
            
            if let initialTribe = parsedInvite.initialTribe {
                self.stashedInitialTribe = initialTribe
                
                if let (host, _) = extractHostAndTribeIdentifier(from: initialTribe) {
                    UserDefaults.Keys.tribesServerIP.set(host)
                }
            }
            
            if let inviterAlias = parsedInvite.inviterAlias {
                self.stashedInviterAlias = inviterAlias
            }
            return parsedInvite.code
        } catch let error {
            print("Parse invite error \(error)")
            return nil
        }
    }
    
    func doInitialInviteSetup() {
        guard let stashedInviteCode = stashedInviteCode else{
            return
        }
        
        if let stashedContactInfo = stashedContactInfo {
            self.stashedContactInfo = nil
            
            makeFriendRequest(
                contactInfo: stashedContactInfo,
                nickname: stashedInviterAlias,
                inviteCode: stashedInviteCode
            )
        }
    }
    
    func createContactForInvite(
        code: String,
        nickname: String
    ) {
        var inviteCode: String? = nil
        do {
            inviteCode = try codeFromInvite(inviteQr: code)
        } catch {
            print("Error getting code from invite")
            return
        }
        
        let contact = UserContact(context: managedContext)
        contact.id = uniqueIntHashFromString(stringInput: UUID().uuidString)
        contact.publicKey = ""//
        contact.isOwner = false//
        contact.nickname = nickname
        contact.createdAt = Date()
        contact.status = UserContact.Status.Pending.rawValue
        contact.createdAt = Date()
        contact.createdAt = Date()
        contact.fromGroup = false
        contact.privatePhoto = false
        contact.tipAmount = 0
        contact.sentInviteCode = inviteCode
        
        let invite = UserInvite(context: managedContext)
        invite.inviteString = code
        invite.status = UserInvite.Status.Ready.rawValue
        contact.invite = invite
        invite.contact = contact
        
        managedContext.saveContext()
    }
    
    func saveConfigFrom(
        lspHost: String,
        tribeServerHost: String,
        defaultTribePubkey: String,
        routerUrl: String?
    ) {
        saveIPAndPortFrom(lspHost: lspHost)
        
        if UserDefaults.Keys.tribesServerIP.get() == nil {
            UserDefaults.Keys.tribesServerIP.set(tribeServerHost)
            UserDefaults.Keys.defaultTribePublicKey.set(defaultTribePubkey)
        }
        
        if let routerUrl = routerUrl {
            self.routerUrl = routerUrl
        }
    }
    
    func saveIPAndPortFrom(lspHost: String) {
        if UserDefaults.Keys.serverIP.get() != nil {
            return
        }
        
        if let components = URLComponents(string: lspHost), let host = components.host {
            if let port = components.port {
                UserDefaults.Keys.serverPORT.set(port)
                UserDefaults.Keys.serverIP.set(host.replacingOccurrences(of: ":\(port)", with: ""))
                isProductionEnv = port == kProdServerPort
            } else {
                UserDefaults.Keys.serverIP.set(host)
                isProductionEnv = false
            }
        } else if let components = URLComponents(string: "https://\(lspHost)"), let host = components.host {
            if let port = components.port {
                UserDefaults.Keys.serverPORT.set(port)
                UserDefaults.Keys.serverIP.set(host.replacingOccurrences(of: ":\(port)", with: ""))
                isProductionEnv = port == kProdServerPort
            } else {
                UserDefaults.Keys.serverIP.set(host)
                isProductionEnv = false
            }
        } else {
            UserDefaults.Keys.serverIP.set(lspHost)
            isProductionEnv = false
        }
    }
}
