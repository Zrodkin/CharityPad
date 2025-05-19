//
//  SquarePaymentProcessingService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//

import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

/// Service responsible for processing payments with Square
class SquarePaymentProcessingService: NSObject {
    // MARK: - Private Properties
    
    private weak var paymentService: SquarePaymentService?
    private weak var authService: SquareAuthService?
    private let idempotencyKeyManager = IdempotencyKeyManager()
    private var paymentHandle: PaymentHandle?
    
    // MARK: - Public Methods
    
    /// Configure the service with necessary dependencies
    func configure(with paymentService: SquarePaymentService, authService: SquareAuthService) {
        self.paymentService = paymentService
        self.authService = authService
    }
    
    /// Process a payment with optional offline support
    func processPayment(amount: Double, allowOffline: Bool, supportsOfflinePayments: Bool, completion: @escaping (Bool, String?) -> Void) {
        // Ensure SDK is initialized
        guard let _ = try? MobilePaymentsSDK.shared else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Square SDK not initialized")
                completion(false, nil)
            }
            return
        }
        
        // Verify authentication
        guard let authService = authService, authService.isAuthenticated else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Not authenticated with Square")
                completion(false, nil)
            }
            return
        }
        
        // Ensure SDK is authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            DispatchQueue.main.async { [weak self] in
                self?.paymentService?.initializeSDK()
                completion(false, nil)
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateIsProcessingPayment(true)
            self?.updatePaymentError(nil)
        }
        
        // Calculate amount in cents
        let amountInCents = UInt(amount * 100)
        
        // Find the view controller to present the payment UI
        guard let presentedVC = getTopViewController() else {
            DispatchQueue.main.async { [weak self] in
                self?.updateIsProcessingPayment(false)
                self?.updatePaymentError("Unable to find view controller to present payment UI")
                completion(false, nil)
            }
            return
        }
        
        // Generate a transaction ID based on amount and timestamp
        let transactionId = "txn_\(Int(amount * 100))_\(Int(Date().timeIntervalSince1970))"
        
        // Get or create idempotency key for this transaction
        let idempotencyKey = idempotencyKeyManager.getKey(for: transactionId)
        
        // Determine the processing mode based on offline support
        let processingMode: ProcessingMode
        if allowOffline && supportsOfflinePayments {
            processingMode = .autoDetect  // Will try online, fall back to offline if needed
        } else {
            processingMode = .onlineOnly  // Only process payments online
        }
        
        // Create payment parameters with appropriate processing mode
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: Money(amount: amountInCents, currency: .USD),
            processingMode: processingMode
        )
        
        // Create prompt parameters
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Create payment delegate
        let paymentDelegate = PaymentDelegate(
            service: self,
            transactionId: transactionId,
            idempotencyManager: idempotencyKeyManager,
            supportsOfflinePayments: supportsOfflinePayments,
            completion: completion
        )
        
        // Start the payment
        paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParameters,
            promptParameters: promptParameters,
            from: presentedVC,
            delegate: paymentDelegate
        )
    }
    
    // MARK: - Private Methods
    
    /// Get the top view controller to present UI
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        return topController
    }
    
    /// Update the is processing payment state in the payment service
    private func updateIsProcessingPayment(_ isProcessing: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.isProcessingPayment = isProcessing
        }
    }
    
    /// Update payment error in the payment service
    private func updatePaymentError(_ error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.paymentError = error
        }
    }
}

// MARK: - PaymentDelegate
extension SquarePaymentProcessingService {
    class PaymentDelegate: NSObject, PaymentManagerDelegate {
        private weak var service: SquarePaymentProcessingService?
        private let transactionId: String
        private let idempotencyManager: IdempotencyKeyManager
        private let supportsOfflinePayments: Bool
        private let completion: (Bool, String?) -> Void
        
        init(service: SquarePaymentProcessingService,
             transactionId: String,
             idempotencyManager: IdempotencyKeyManager,
             supportsOfflinePayments: Bool,
             completion: @escaping (Bool, String?) -> Void) {
            self.service = service
            self.transactionId = transactionId
            self.idempotencyManager = idempotencyManager
            self.supportsOfflinePayments = supportsOfflinePayments
            self.completion = completion
            super.init()
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.service?.updateIsProcessingPayment(false)
                print("Payment successful with ID: \(String(describing: payment.id))")
                
                // Keep idempotency key for successful payments
                self.completion(true, payment.id)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.service?.updateIsProcessingPayment(false)
                
                // Enhanced error handling with specific messages for each error type
                let nsError = error as NSError
                
                if let paymentError = PaymentError(rawValue: nsError.code) {
                    switch paymentError {
                    case .idempotencyKeyReused:
                        // This indicates a duplicate payment attempt, do not delete the key
                        self.service?.updatePaymentError("This payment appears to be a duplicate. Please check if the payment was already processed.")
                        
                    case .deviceTimeDoesNotMatchServerTime:
                        self.service?.updatePaymentError("Your device's time is incorrect. Please check your device settings and try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .invalidPaymentParameters:
                        self.service?.updatePaymentError("Invalid payment details. Please try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .locationPermissionNeeded:
                        self.service?.updatePaymentError("Location access is required. Please grant permission in Settings and try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .noNetwork:
                        // Check if offline payments are enabled before removing key
                        if self.supportsOfflinePayments {
                            self.service?.updatePaymentError("No network connection. Payment will be processed when connection is restored.")
                            // Don't remove key - it will be used when processing offline
                        } else {
                            self.service?.updatePaymentError("No network connection. Please check your connection and try again.")
                            self.idempotencyManager.removeKey(for: self.transactionId)
                        }
                        
                    case .noNetworkAndMerchantNotOptedIntoOfflineProcessing:
                        self.service?.updatePaymentError("No network connection and offline payments are not available for your account.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .merchantNotOptedIntoOfflineProcessing:
                        self.service?.updatePaymentError("Your Square account is not enabled for offline payments.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .notAuthorized:
                        self.service?.updatePaymentError("Not connected to Square. Please reconnect your account.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .offlineStoredAmountExceeded:
                        self.service?.updatePaymentError("Offline payment limit reached. Please connect to the internet to process stored payments.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .offlineTransactionAmountExceeded:
                        self.service?.updatePaymentError("This amount exceeds the offline payment limit. Please use a smaller amount or try when online.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .paymentAlreadyInProgress:
                        self.service?.updatePaymentError("A payment is already in progress. Please wait for it to complete.")
                        // Don't remove the key since we're not abandoning this payment
                        
                    case .sandboxUnsupportedForOfflineProcessing:
                        self.service?.updatePaymentError("Offline payments are not supported in sandbox mode.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .timedOut:
                        self.service?.updatePaymentError("Payment timed out. Please try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .unsupportedMode:
                        self.service?.updatePaymentError("Unsupported device mode. Please exit split screen or other modes and try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    case .invalidPaymentSource, .unexpected:
                        self.service?.updatePaymentError("An unexpected error occurred. Please try again.")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                        
                    @unknown default:
                        self.service?.updatePaymentError("Payment failed: \(error.localizedDescription)")
                        self.idempotencyManager.removeKey(for: self.transactionId)
                    }
                } else {
                    // Handle unknown errors
                    self.service?.updatePaymentError("Payment failed: \(error.localizedDescription)")
                    self.idempotencyManager.removeKey(for: self.transactionId)
                }
                
                print("Payment failed: \(error.localizedDescription)")
                self.completion(false, nil)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Remove idempotency key for canceled payments
                self.idempotencyManager.removeKey(for: self.transactionId)
                
                self.service?.updateIsProcessingPayment(false)
                self.service?.updatePaymentError("Payment was canceled")
                print("Payment was canceled by user")
                self.completion(false, nil)
            }
        }
    }
}
