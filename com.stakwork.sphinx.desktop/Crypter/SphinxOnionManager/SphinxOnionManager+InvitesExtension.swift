//
//  SphinxOnionManager+InvitesExtension.swift
//  sphinx
//
//  Created by James Carucci on 2/27/24.
//  Copyright © 2024 sphinx. All rights reserved.
//

import Foundation

extension SphinxOnionManager{//invites related
    
    func uniqueIntHashFromString(stringInput:String) -> Int{
        return Int(Int32(stringInput.hashValue & 0x7FFFFFFF))
    }
    
    func requestInviteCode(amountMsat: Int) {
        guard let seed = getAccountSeed(),
              let selfContact = UserContact.getSelfContact(),
              let nickname = selfContact.nickname else
        {
            return
        }
        
        do {
            let rr = try makeInvite(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                host: self.server_IP,
                amtMsat: UInt64(amountMsat),
                myAlias: nickname,
                tribeHost: "\(server_IP):8801",
                tribePubkey: defaultTribePubkey
            )
            
            let _ = handleRunReturn(rr: rr)
        } catch {}
    }
    
    func redeemInvite(
        inviteCode: String,
        mnemonic: String
    ) {
        guard let seed = getAccountSeed(mnemonic: mnemonic) else{
            return
        }
        do {
            let rr = try processInvite(
                seed: seed,
                uniqueTime: getTimeWithEntropy(),
                state: loadOnionStateAsData(),
                inviteQr: inviteCode
            )
            
            let _ = handleRunReturn(rr: rr)
            
            if let lsp = rr.lspHost {
                self.server_IP = lsp
            }
            
            if let initialTribe = rr.initialTribe, let (host, _) = extractHostAndTribeIdentifier(from: initialTribe) {
                API.kTribesServer = host
            }
            
            self.stashedContactInfo = rr.inviterContactInfo
            self.stashedInitialTribe = rr.initialTribe
            self.stashedInviteCode = inviteCode
            self.stashedInviterAlias = rr.inviterAlias
        } catch {}
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
    
}
