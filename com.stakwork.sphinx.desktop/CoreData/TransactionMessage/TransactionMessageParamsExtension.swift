//
//  TransactionMessageParamsExtension.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation
import CoreData

extension TransactionMessage {    
    static func getBoostMessageParams(
        contact: UserContact? = nil,
        chat: Chat? = nil,
        replyingMessage: TransactionMessage? = nil
    ) -> [String: AnyObject]? {
        
        if let replyingMessage = replyingMessage, let replyUUID = replyingMessage.uuid, !replyUUID.isEmpty {
            var parameters = [String : AnyObject]()
            
            parameters["boost"] = true as AnyObject?
            parameters["text"] = "" as AnyObject?
            
            if let chat = chat {
                parameters["chat_id"] = chat.id as AnyObject?
            } else if let contact = contact {
                parameters["contact_id"] = contact.id as AnyObject?
            }
            
            let pricePerMessage = (chat?.pricePerMessage?.intValue ?? 0)
            let escrowAmount = (chat?.escrowAmount?.intValue ?? 0)
            let tipAmount: Int = UserDefaults.Keys.tipAmount.get(defaultValue: 100)
            parameters["amount"] = pricePerMessage + escrowAmount + tipAmount as AnyObject?
            parameters["message_price"] = pricePerMessage + escrowAmount as AnyObject?
            
            parameters["reply_uuid"] = replyUUID as AnyObject?
            return parameters
        }
        return nil
    }
    
    static func getFeedBoostMessageParams(
        contact: UserContact? = nil,
        chat: Chat? = nil,
        text: String
    ) -> [String: AnyObject]? {
        
        var parameters = [String : AnyObject]()
        
        parameters["boost"] = true as AnyObject?
        parameters["text"] = text as AnyObject?
        
        if let chat = chat {
            parameters["chat_id"] = chat.id as AnyObject?
        } else if let contact = contact {
            parameters["contact_id"] = contact.id as AnyObject?
        }
        
        let pricePerMessage = (chat?.pricePerMessage?.intValue ?? 0)
        let escrowAmount = (chat?.escrowAmount?.intValue ?? 0)
        parameters["amount"] = pricePerMessage + escrowAmount as AnyObject?
        parameters["message_price"] = pricePerMessage + escrowAmount as AnyObject?
        
        return parameters
    }
}
