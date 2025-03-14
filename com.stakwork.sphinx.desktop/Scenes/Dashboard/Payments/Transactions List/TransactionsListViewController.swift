//
//  TransactionsListViewController.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 22/11/2023.
//  Copyright © 2023 Tomas Timinskas. All rights reserved.
//

import Cocoa
import ObjectMapper

class TransactionsListViewController: NSViewController {
    
    @IBOutlet weak var transactionsCollectionView: NSCollectionView!
    @IBOutlet weak var noResultsLabel: NSTextField!
    @IBOutlet weak var loadingWheel: NSProgressIndicator!
    
    var transactionsDataSource : TransactionsDataSource!
    
    var didReachLimit = false
    let itemsPerPage : UInt32 = 50
    
    var succeededPaymentHashes: [String] = []
    
    static func instantiate() -> TransactionsListViewController {
        
        let viewController = StoryboardScene.Payments.transactionsListVC.instantiate()
        
        return viewController
    }
    
    var loading = false {
        didSet {
            LoadingWheelHelper.toggleLoadingWheel(loading: loading, loadingWheel: loadingWheel, color: NSColor.Sphinx.Text, controls: [])
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        transactionsCollectionView.alphaValue = 0.0
        noResultsLabel.alphaValue = 0.0
        configureCollectionView()
    }
    
    func configureCollectionView() {
        transactionsDataSource = TransactionsDataSource(collectionView: transactionsCollectionView, delegate: self)
        transactionsCollectionView.delegate = transactionsDataSource
        transactionsCollectionView.dataSource = transactionsDataSource
        
        loading = true
        
        SphinxOnionManager.sharedInstance.getTransactionsHistory(
            paymentsHistoryCallback: handlePaymentHistoryCompletion,
            itemsPerPage: itemsPerPage,
            sinceTimestamp: UInt64(Date().timeIntervalSince1970)
        )
    }
    
    func handlePaymentHistoryCompletion(
        jsonString: String?,
        error: String?
    ) {
        if let _ = error {
            setNoResultsLabel(count: 0)
            loading = false
            
            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "error.loading.transactions".localized
            )
            return
        }
        
        var history = [PaymentTransaction]()

        if let jsonString = jsonString,
           let results = Mapper<PaymentTransactionFromServer>().mapArray(JSONString: jsonString) {
            
            succeededPaymentHashes += (results.filter({ $0.isSucceeded() })).compactMap({ $0.rhash })
            
            let msgIndexes = results.compactMap({ $0.msg_idx })
            let msgPmtHashes = results.compactMap({ $0.rhash })
            var messages = TransactionMessage.fetchTransactionMessagesForHistory()
            let messagesMatching = TransactionMessage.fetchTransactionMessagesForHistoryWith(msgIndexes: msgIndexes, msgPmtHashes: msgPmtHashes)
            messages.append(contentsOf: messagesMatching)
            
            for result in results {
                
                if let rHash = result.rhash, result.isFailed() && succeededPaymentHashes.contains(rHash) {
                    continue
                }
                
                if let localHistoryMessage = messages.filter({ $0.id == result.msg_idx ?? -1 }).first {
                    let paymentTransaction = PaymentTransaction(fromTransactionMessage: localHistoryMessage, ts: result.ts)
                    history.append(paymentTransaction)
                    continue
                }
                
                if let localHistoryMessage = messages.filter({ $0.paymentHash == result.rhash ?? "" }).first {
                    let paymentTransaction = PaymentTransaction(fromTransactionMessage: localHistoryMessage, ts: result.ts)
                    history.append(paymentTransaction)
                    continue
                }
                
                let amountThreshold = 5000 // msats
                let timestampThreshold: TimeInterval = 10 // seconds
                
                if let localHistoryMessage = messages.filter({
                    guard let messageAmountSats = $0.amount?.intValue,
                          let messageTimestamp = $0.date?.timeIntervalSince1970 else {
                        return false
                    }
                    let messageAmountMsats = messageAmountSats * 1000
                    let resultAmountMsats = result.amt_msat ?? 0
                    let resultTimestamp = TimeInterval(result.ts ?? 0) / 1000
                    
                    return resultAmountMsats > amountThreshold &&
                           resultAmountMsats == messageAmountMsats &&
                           abs(resultTimestamp - messageTimestamp) <= timestampThreshold
                }).first {
                    let paymentTransaction = PaymentTransaction(fromTransactionMessage: localHistoryMessage, ts: result.ts)
                    history.append(paymentTransaction)
                    continue
                }
                
                let newHistory = PaymentTransaction(fromFetchedParams: result)
                history.append(newHistory)
            }
        }
        
        history = history.filter({ ($0.amount ?? 0) >= 1 })
        history = history.sorted { $0.getDate() > $1.getDate() }
        
        setNoResultsLabel(count: history.count)
        checkResultsLimit(count: history.count)
        transactionsDataSource.loadTransactions(transactions: history)
        loading = false
    }
    
    func setNoResultsLabel(count: Int) {
        noResultsLabel.alphaValue = count > 0 ? 0.0 : 1.0
    }
    
    func checkResultsLimit(count: Int) {
        didReachLimit = count < itemsPerPage
    }
    
    deinit {
        print("here is the TransactionsListViewController going to sleep")
    }
}

extension TransactionsListViewController : TransactionsDataSourceDelegate {
    func shouldLoadMoreTransactions() {
        if didReachLimit {
            return
        }
        
        guard let oldestTransaction = transactionsDataSource.transactions.last else {
            return
        }
        
        let oldestTimestamp = UInt64(oldestTransaction.getDate().timeIntervalSince1970)
        
        SphinxOnionManager.sharedInstance.getTransactionsHistory(
            paymentsHistoryCallback: handlePaymentHistoryCompletion,
            itemsPerPage: itemsPerPage,
            sinceTimestamp: oldestTimestamp
        )
    }
}
