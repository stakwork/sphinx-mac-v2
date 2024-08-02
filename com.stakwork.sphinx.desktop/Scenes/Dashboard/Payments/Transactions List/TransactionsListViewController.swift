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
            checkResultsLimit(count: 0)
            transactionsCollectionView.alphaValue = 0.0
            loading = false

            AlertHelper.showAlert(
                title: "generic.error.title".localized,
                message: "error.loading.transactions".localized
            )
            return
        }
        
        // 1. Pull history with messages from local DB
        var history = [PaymentTransaction]()
        
        let messages = TransactionMessage.fetchTransactionMessagesForHistory()
        
        for message in messages {
            history.append(PaymentTransaction(fromTransactionMessage: message))
        }
        
        // 2. Collect and process remote transactions not accounted for with messages
        if let jsonString = jsonString, let results = Mapper<PaymentTransactionFromServer>().mapArray(JSONString: jsonString) {
            
            let localHistoryIndices = messages.map { $0.id }
            let localHistoryPaymentHashes = messages.compactMap { $0.paymentHash } // Ensure no nil values
            
            let unAccountedResults = results.filter { result in
                let msgIdxUnaccounted = !localHistoryIndices.contains(result.msg_idx ?? -21)
                let rhashUnaccounted = !localHistoryPaymentHashes.contains(result.rhash ?? "")
                
                // Check for amount and timestamp condition
                let amountThreshold = 5000 // msats
                let timestampThreshold: TimeInterval = 10 // seconds
                
                let similarTransactionExists = messages.contains { message in
                    guard let messageAmountSats = message.amount?.intValue,
                          let messageTimestamp = message.date?.timeIntervalSince1970 else {
                        return false
                    }
                    
                    let messageAmountMsats = messageAmountSats * 1000
                    let resultAmountMsats = result.amt_msat ?? 0
                    let resultTimestamp = TimeInterval(result.ts ?? 0) / 1000
                    
                    return resultAmountMsats > amountThreshold &&
                           resultAmountMsats == messageAmountMsats &&
                           abs(resultTimestamp - messageTimestamp) <= timestampThreshold
                }
                
                return (msgIdxUnaccounted && rhashUnaccounted) && !similarTransactionExists
            }
            
            for result in unAccountedResults {
                let newHistory = PaymentTransaction(fromFetchedParams: result)
                history.append(newHistory)
            }
        }
        
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
        
        loading = true
        
        SphinxOnionManager.sharedInstance.getTransactionsHistory(
            paymentsHistoryCallback: handlePaymentHistoryCompletion,
            itemsPerPage: itemsPerPage,
            sinceTimestamp: oldestTimestamp
        )
    }
}
