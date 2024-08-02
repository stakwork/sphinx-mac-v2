//
//  FeedBoostHelper.swift
//  sphinx
//
//  Created by Tomas Timinskas on 20/01/2022.
//  Copyright © 2022 sphinx. All rights reserved.
//

import Foundation
import CoreData

class FeedBoostHelper : NSObject {
    
    var contentFeed: ContentFeed? = nil
    var chat: Chat? = nil
    
    func configure(
        with feedId: String,
        and chat: Chat?
    ) {
        self.contentFeed = ContentFeed.getFeedById(feedId: feedId)
        self.chat = chat
    }
    
    func getBoostMessage(
        itemID: String,
        amount: Int,
        currentTime: Int = 0
    ) -> String? {
        
        guard let contentFeed = self.contentFeed else {
            return nil
        }
        
        if amount == 0 {
            return nil
        }
        
        let feedID = contentFeed.feedID
        
        return "{\"feedID\":\"\(feedID)\",\"itemID\":\"\(itemID)\",\"ts\":\(currentTime),\"amount\":\(amount)}"
    }
    
    func processPayment(
        itemID: String,
        amount: Int,
        currentTime: Int = 0
    ) {
        processPaymentsFor(
            itemID: itemID,
            amount: amount,
            currentTime: currentTime
        )
    }
    
    func processPaymentsFor(
        itemID: String,
        amount: Int,
        currentTime: Int
    ) {
        let destinations = contentFeed?.destinationsArray ?? []
        
        if
            let _ = contentFeed,
            destinations.isEmpty == false
        {
            streamSats(
                feedDestinations: destinations,
                amount: amount,
                itemID: itemID,
                currentTime: currentTime
            )
        }
    }
    
    func streamSats(
        feedDestinations: [ContentFeedPaymentDestination],
        amount: Int,
        itemID: String,
        currentTime: Int
    ) {
        
        let tipAmount: Int = UserDefaults.Keys.tipAmount.get(defaultValue: 100)
        
        guard let feedID = contentFeed?.feedID else {
            return
        }
        
        for (index, d) in feedDestinations.enumerated() {
            if d.type ?? "" == "node" {
                let amount = Double(tipAmount) / 100 * d.split
                
                let text = """
                {
                    "feedID": "\(feedID)",
                    "itemID": "\(itemID)",
                    "ts": \(currentTime)
                }
                """
                
                guard let data = text.data(using: .utf8), let pubkey = d.address, pubkey.isPubKey else {
                    continue
                }
                
                DelayPerformedHelper.performAfterDelay(seconds: 0.5 * Double(index), completion: {
                    SphinxOnionManager.sharedInstance.keysend(
                        pubkey: pubkey,
                        amt: Int(amount),
                        data: data,
                        completion: { _ in }
                    )
                })
            }
        }
    }
    

    func sendBoostMessage(
        message: String,
        episodeId: String,
        amount: Int,
        completion: @escaping ((TransactionMessage?, Bool) -> ())
    ) {
        guard let params = TransactionMessage.getFeedBoostMessageParams(
            contact: nil,
            chat: chat,
            text: message
        ), let chat = chat else {
            return
        }
        
        SphinxOnionManager.sharedInstance.sendFeedBoost(
            params: params,
            chat: chat,
            completion: { message in
                if let message = message {
                    completion(message, true)
//                    self.trackBoostAction(episodeId: episodeId, amount: amount)
                } else {
                    completion(nil, false)
                }
            }
        )
    }
    
    func trackBoostAction(
        episodeId: String,
        amount: Int
    ) {
        if let contentFeedItem: ContentFeedItem = ContentFeedItem.getItemWith(itemID: episodeId) {
            ActionsManager.sharedInstance.trackContentBoost(amount: amount, feedItem: contentFeedItem)
        }
    }
}
