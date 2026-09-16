//
//  InvoiceAlreadyPaidTests.swift
//  com.stakwork.sphinx.desktopTests
//
//  Local already-paid invoice check, in-flight guard, and handleRunReturn
//  skip-path coverage. No E2E / no real FFI.
//

import XCTest
@testable import com_stakwork_sphinx_desktop

final class InvoiceAlreadyPaidTests: XCTestCase {

    var manager: SphinxOnionManager!
    private var savedMatchers: Set<String> = []

    private let alreadyPaidHash = "paid-hash-abc"
    private let unpaidHash = "unpaid-hash-xyz"
    private let mixerAlreadyPaid = "CONFIRMED_MIXER_ALREADY_PAID"

    override func setUp() {
        super.setUp()
        SphinxOnionManager.resetSharedInstance()
        manager = SphinxOnionManager.sharedInstance
        savedMatchers = SphinxOnionManager.invoiceAlreadyPaidErrorMatchers
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = []
        manager.resetPaymentAttemptTestState()
    }

    override func tearDown() {
        manager.resetPaymentAttemptTestState()
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = savedMatchers
        SphinxOnionManager.resetSharedInstance()
        super.tearDown()
    }

    // MARK: - Helpers

    private func invoiceDetails(
        paymentHash: String,
        value: Int? = 1000,
        hopHints: [String]? = ["hint"]
    ) -> ParseInvoiceResult {
        ParseInvoiceResult(
            value: value,
            paymentHash: paymentHash,
            pubkey: "test-pubkey",
            hopHints: hopHints
        )
    }

    private func stubInvoice(
        paymentHash: String,
        value: Int? = 1000,
        hopHints: [String]? = ["hint"]
    ) {
        let details = invoiceDetails(
            paymentHash: paymentHash,
            value: value,
            hopHints: hopHints
        )
        manager.invoiceDetailsProvider = { _ in details }
    }

    // MARK: - Matcher

    func test_isInvoiceAlreadyPaidError_returnsFalseWhenMatchersEmpty() {
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError(nil))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError(""))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError("invoice settled"))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError("already paid"))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError(mixerAlreadyPaid))
    }

    func test_isInvoiceAlreadyPaidError_matchesOnlyConfirmedMixerString() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        XCTAssertTrue(manager.isInvoiceAlreadyPaidError(mixerAlreadyPaid))
        XCTAssertTrue(manager.isInvoiceAlreadyPaidError("prefix \(mixerAlreadyPaid) suffix"))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError("invoice settled"))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError("already paid"))
        XCTAssertFalse(manager.isInvoiceAlreadyPaidError(nil))
    }

    func test_isInvoiceAlreadyPaidSphinxError_matchesSendFailedAssociatedValue() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        XCTAssertTrue(
            manager.isInvoiceAlreadyPaidSphinxError(
                SphinxError.SendFailed(r: mixerAlreadyPaid)
            )
        )
        XCTAssertFalse(
            manager.isInvoiceAlreadyPaidSphinxError(
                SphinxError.SendFailed(r: "unrelated")
            )
        )
        XCTAssertFalse(
            manager.isInvoiceAlreadyPaidSphinxError(
                SphinxError.BadArgs(r: mixerAlreadyPaid)
            )
        )
    }

    // MARK: - Settled lookup predicate

    func test_settledPaymentPredicate_matchesConfirmedAndReceivedRegardlessOfType() {
        let predicate = TransactionMessage.settledPaymentPredicate(
            forPaymentHash: alreadyPaidHash
        )
        let confirmedPayment: [String: Any] = [
            "paymentHash": alreadyPaidHash,
            "status": TransactionMessage.TransactionMessageStatus.confirmed.rawValue,
            "type": TransactionMessage.TransactionMessageType.payment.rawValue
        ]
        let receivedInvoice: [String: Any] = [
            "paymentHash": alreadyPaidHash,
            "status": TransactionMessage.TransactionMessageStatus.received.rawValue,
            "type": TransactionMessage.TransactionMessageType.invoice.rawValue
        ]
        XCTAssertTrue(predicate.evaluate(with: confirmedPayment))
        XCTAssertTrue(predicate.evaluate(with: receivedInvoice))
    }

    func test_settledPaymentPredicate_rejectsFailedAndPending() {
        let predicate = TransactionMessage.settledPaymentPredicate(
            forPaymentHash: alreadyPaidHash
        )
        let failed: [String: Any] = [
            "paymentHash": alreadyPaidHash,
            "status": TransactionMessage.TransactionMessageStatus.failed.rawValue
        ]
        let pending: [String: Any] = [
            "paymentHash": alreadyPaidHash,
            "status": TransactionMessage.TransactionMessageStatus.pending.rawValue
        ]
        XCTAssertFalse(predicate.evaluate(with: failed))
        XCTAssertFalse(predicate.evaluate(with: pending))
    }

    func test_hasSettledPayment_returnsFalseForEmptyHash() {
        XCTAssertFalse(TransactionMessage.hasSettledPayment(forPaymentHash: ""))
    }

    // MARK: - Local short-circuit

    func test_payInvoice_doesNotCallFFI_whenSettledHashDetected() {
        stubInvoice(paymentHash: alreadyPaidHash)
        manager.hasSettledPaymentOverride = { $0 == self.alreadyPaidHash }

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoice(invoice: "lnbc-already-paid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 0)
        XCTAssertEqual(manager.routeFetchCallCount, 0)
    }

    func test_payInvoiceFromSB_doesNotCallFFI_whenSettledHashDetected() {
        stubInvoice(paymentHash: alreadyPaidHash)
        manager.hasSettledPaymentOverride = { $0 == self.alreadyPaidHash }

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoiceFromSB(invoice: "lnbc-already-paid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 0)
        XCTAssertEqual(manager.routeFetchCallCount, 0)
    }

    func test_payInvoiceMessage_alertsAndDoesNotCallFFI_whenSettledHashDetected() {
        stubInvoice(paymentHash: alreadyPaidHash)
        manager.hasSettledPaymentOverride = { $0 == self.alreadyPaidHash }

        var alertMessage: String?
        manager.alreadyPaidAlertHandler = { alertMessage = $0 }

        manager.payInvoiceMessage(
            invoice: "lnbc-already-paid",
            paymentHash: alreadyPaidHash
        )

        XCTAssertEqual(alertMessage, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 0)
        XCTAssertEqual(manager.routeFetchCallCount, 0)
    }

    func test_payInvoice_zeroAmountStillShortCircuitsOnSettledHash() {
        stubInvoice(paymentHash: alreadyPaidHash, value: nil)
        manager.hasSettledPaymentOverride = { $0 == self.alreadyPaidHash }

        var callbackSuccess: Bool?
        manager.payInvoice(invoice: "lnbc-zero") { success, _ in
            callbackSuccess = success
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(manager.sphinxPayCallCount, 0)
        XCTAssertEqual(manager.routeFetchCallCount, 0)
    }

    func test_payInvoice_allowsRetryForUnsettledHash() {
        stubInvoice(paymentHash: unpaidHash)
        manager.hasSettledPaymentOverride = { _ in false }
        manager.checkAndFetchRouteOverride = { callback in callback(false) }

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoice(invoice: "lnbc-unpaid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertNotEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.routeFetchCallCount, 1)
    }

    // MARK: - In-flight guard

    func test_inFlightGuard_secondSubmitDoesNotFetchRoute() {
        stubInvoice(paymentHash: unpaidHash)
        manager.hasSettledPaymentOverride = { _ in false }

        var heldCallback: ((Bool) -> Void)?
        manager.checkAndFetchRouteOverride = { callback in
            heldCallback = callback
        }

        var firstResult: Bool?
        var secondSuccess: Bool?
        var secondError: String?

        manager.payInvoice(invoice: "lnbc-unpaid") { success, _ in
            firstResult = success
        }
        manager.payInvoice(invoice: "lnbc-unpaid") { success, errorMsg in
            secondSuccess = success
            secondError = errorMsg
        }

        XCTAssertEqual(manager.routeFetchCallCount, 1)
        XCTAssertEqual(secondSuccess, false)
        XCTAssertEqual(secondError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertNil(firstResult)

        heldCallback?(false)
        XCTAssertEqual(firstResult, false)
        XCTAssertEqual(manager.sphinxPayCallCount, 0)
    }

    // MARK: - Double-success fix / network already-paid

    func test_payInvoiceFromLSP_callbacksFalse_onAlreadyPaidRunReturn() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        stubInvoice(paymentHash: unpaidHash, hopHints: nil)
        manager.hasSettledPaymentOverride = { _ in false }
        manager.simulatedPayRunReturn = RunReturn.empty(
            error: mixerAlreadyPaid,
            newBalance: 99_000,
            msgs: [
                Msg(
                    message: nil,
                    type: nil,
                    uuid: nil,
                    tag: nil,
                    index: nil,
                    sender: nil,
                    msat: nil,
                    timestamp: nil,
                    sentTo: nil,
                    fromMe: nil,
                    paymentHash: unpaidHash,
                    error: mixerAlreadyPaid
                )
            ]
        )

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoiceFromLSP(invoice: "lnbc-unpaid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 1)
        XCTAssertEqual(manager.handleBalanceUpdateCallCount, 0)
        XCTAssertEqual(manager.processInvoicePaidCallCount, 0)
        XCTAssertEqual(manager.handleInvoiceSentStatusCallCount, 0)
        XCTAssertEqual(manager.handleMessageStatusByTagCallCount, 0)
        XCTAssertEqual(manager.processGenericMessagesCallCount, 0)
    }

    func test_finalizePayInvoice_callbacksFalse_onSendFailedAssociatedValue() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        stubInvoice(paymentHash: unpaidHash)
        manager.hasSettledPaymentOverride = { _ in false }
        manager.simulatedPayError = SphinxError.SendFailed(r: mixerAlreadyPaid)

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.finalizePayInvoice(
            invoice: "lnbc-unpaid",
            hasRouteHint: true,
            amount: 1000,
            paymentHash: unpaidHash
        ) { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 1)
        XCTAssertEqual(manager.handleBalanceUpdateCallCount, 0)
    }

    func test_payInvoice_noRouteHint_doesNotForceSucceedAfterLSPAlreadyPaid() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        stubInvoice(paymentHash: unpaidHash, hopHints: nil)
        manager.hasSettledPaymentOverride = { _ in false }
        manager.checkAndFetchRouteOverride = { callback in callback(false) }
        manager.simulatedPayError = SphinxError.SendFailed(r: mixerAlreadyPaid)

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoice(invoice: "lnbc-unpaid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 1)
    }

    func test_payInvoiceFromSB_noRouteHint_doesNotForceSucceedAfterLSPAlreadyPaid() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        stubInvoice(paymentHash: unpaidHash, hopHints: nil)
        manager.hasSettledPaymentOverride = { _ in false }
        manager.simulatedPayRunReturn = RunReturn.empty(error: mixerAlreadyPaid)

        var callbackSuccess: Bool?
        var callbackError: String?
        manager.payInvoiceFromSB(invoice: "lnbc-unpaid") { success, errorMsg in
            callbackSuccess = success
            callbackError = errorMsg
        }

        XCTAssertEqual(callbackSuccess, false)
        XCTAssertEqual(callbackError, manager.invoiceAlreadyPaidLocalizedMessage)
        XCTAssertEqual(manager.sphinxPayCallCount, 1)
    }

    // MARK: - handleRunReturn skip scope

    func test_handleRunReturn_skipsSideEffects_onAlreadyPaidErrorWithNewBalance() {
        SphinxOnionManager.invoiceAlreadyPaidErrorMatchers = [mixerAlreadyPaid]
        let rr = RunReturn.empty(
            error: mixerAlreadyPaid,
            newBalance: 42_000,
            msgs: [
                Msg(
                    message: nil,
                    type: nil,
                    uuid: nil,
                    tag: nil,
                    index: nil,
                    sender: nil,
                    msat: nil,
                    timestamp: nil,
                    sentTo: nil,
                    fromMe: nil,
                    paymentHash: unpaidHash,
                    error: mixerAlreadyPaid
                )
            ]
        )

        let _ = manager.handleRunReturn(rr: rr)

        XCTAssertEqual(manager.handleBalanceUpdateCallCount, 0)
        XCTAssertEqual(manager.processInvoicePaidCallCount, 0)
        XCTAssertEqual(manager.handleInvoiceSentStatusCallCount, 0)
        XCTAssertEqual(manager.handleMessageStatusByTagCallCount, 0)
        XCTAssertEqual(manager.processGenericMessagesCallCount, 0)
        XCTAssertTrue(manager.isPaymentHashPaid(unpaidHash))
    }

    func test_handleRunReturn_unrelatedError_stillUpdatesBalance() {
        let rr = RunReturn.empty(error: "no route found", newBalance: 7_000)

        let _ = manager.handleRunReturn(rr: rr)

        XCTAssertEqual(manager.handleBalanceUpdateCallCount, 1)
        XCTAssertEqual(manager.processInvoicePaidCallCount, 1)
        XCTAssertEqual(manager.handleInvoiceSentStatusCallCount, 1)
        XCTAssertEqual(manager.handleMessageStatusByTagCallCount, 1)
    }
}
