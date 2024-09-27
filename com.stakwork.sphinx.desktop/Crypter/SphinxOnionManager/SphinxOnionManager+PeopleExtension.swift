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
        query: String,
        completion: @escaping ((String, String, String, [String: AnyObject])?) -> ()
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
        
        API.sharedInstance.checkPeopleProfileWith(
            publicKey: pubkey,
            callback: { success in
                if success {
                    processQueryAndAuthorize(query: query, completion: completion)
                } else {
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
                        token: token,
                        alias: alias,
                        publicKey: pubkey,
                        routeHint: routeHint,
                        callback: { succes in
                            if succes {
                                processQueryAndAuthorize(query: query, completion: completion)
                            } else {
                                completion(nil)
                            }
                        }
                    )
                }
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
            query: String,
            completion: @escaping ((String, String, String, [String: AnyObject])?) -> ()
        ) {
            if let components = URLComponents(string: "sphinx.chat://?\(query)") {
                var queryParams: [String: String] = [:]
                
                components.queryItems?.forEach { queryItem in
                    queryParams[queryItem.name] = queryItem.value
                }
                
                guard let host = queryParams["host"],
                      let challenge = queryParams["challenge"] else {
                    completion(nil)
                    return
                }
                
                authorizeWithChallenge(host: host, challenge: challenge) { success, token, params in
                    if success {
                        completion((host, challenge, token, params))
                    } else {
                        completion(nil)
                    }
                }
            } else {
                completion(nil)
            }
        }
    }
}
