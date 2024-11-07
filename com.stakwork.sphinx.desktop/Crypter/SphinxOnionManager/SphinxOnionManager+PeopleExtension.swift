//
//  SphinxOnionManager+PeopleExtension.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 27/09/2024.
//  Copyright © 2024 Tomas Timinskas. All rights reserved.
//

import Foundation
import SwiftyJSON

extension SphinxOnionManager {
    func processPeopleAuthChallenge(
        host: String,
        challenge: String,
        completion: @escaping ((String, [String: AnyObject])?) -> ()
    ) {
        guard let seed = getAccountSeed(),
              let owner = UserContact.getOwner(),
              let pubkey = owner.publicKey,
              let routeHint = owner.routeHint,
              let alias = owner.nickname else
        {
            completion(nil)
            return
        }

        let photoUrl = owner.avatarUrl ?? ""
        
        var token: String = ""
        
        do {
            let idx: UInt64 = 0
            
            token = try Sphinx.signedTimestamp(
                seed: seed,
                idx: idx,
                time: self.getTimeWithEntropy(),
                network: self.network
            )
        } catch {
            completion(nil)
            return
        }
        
        API.sharedInstance.createPeopleProfileWith(
            host: host,
            token: token,
            alias: alias,
            imageUrl: owner.getPhotoUrl(),
            publicKey: pubkey,
            routeHint: routeHint,
            callback: { _ in
                processQueryAndAuthorize(
                    host: host,
                    challenge: challenge,
                    completion: completion
                )
            }
        )

        func authorizeWithChallenge(
            host: String,
            challenge: String,
            completion: @escaping (Bool, String, [String: AnyObject]) -> ()
        ) {
            do {
                let idx: UInt64 = 0
                
                let token = try Sphinx.signedTimestamp(
                    seed: seed,
                    idx: idx,
                    time: getTimeWithEntropy(),
                    network: network
                )
                
                let sig = try Sphinx.signBase64(
                    seed: seed,
                    idx: idx,
                    time: getTimeWithEntropy(),
                    network: network,
                    msg: challenge
                )

                let params: [String: AnyObject] = [
                    "pubkey": pubkey as AnyObject,
                    "alias": alias as AnyObject,
                    "photo_url": photoUrl as AnyObject,
                    "route_hint": routeHint as AnyObject,
                    "price_to_meet": 0 as AnyObject,
                    "verification_signature": sig as AnyObject
                ]

                API.sharedInstance.authorizeExternal(
                    host: host,
                    challenge: challenge,
                    token: token,
                    params: params,
                    callback: { success in
                        completion(success, token, params)
                    }
                )
            } catch {
                completion(false, "", [:])
            }
        }
        
        func processQueryAndAuthorize(
            host: String,
            challenge: String,
            completion: @escaping ((String, [String: AnyObject])?) -> ()
        ) {
            authorizeWithChallenge(host: host, challenge: challenge) { success, token, params in
                if success {
                    completion((token, params))
                } else {
                    completion(nil)
                }
            }
        }
    }
}
