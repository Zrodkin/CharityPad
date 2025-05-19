import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

/// Service responsible for handling Apple Tap to Pay functionality
class SquareTapToPayService: NSObject {
    // MARK: - Private Properties
    
    private weak var paymentService: SquarePaymentService?
    private weak var authService: SquareAuthService?
    private let idempotencyKeyManager = IdempotencyKeyManager()
    private var paymentHandle: PaymentHandle?
    private var tapToPaySettings: TapToPaySettings?
    
    // MARK: - Public Methods
    
    /// Configure the service with the payment service
    func configure(with paymentService: SquarePaymentService, authService: SquareAuthService) {
        self.paymentService = paymentService
        self.authService = authService
        
        // Initialize Tap to Pay settings reference if SDK is available
        if let _ = try? MobilePaymentsSDK.shared {
            self.tapToPaySettings = MobilePaymentsSDK.shared.tapToPaySettings
        }
    }
    
    /// Check if device supports Tap to Pay
    func checkTapToPayCapability() {
        guard let tapToPaySettings = self.tapToPaySettings else {
            updateSupportsTapToPay(false)
            return
        }
        
        // Check if device is capable of Tap to Pay
        let isDeviceCapable = tapToPaySettings.isDeviceCapable
        
        updateSupportsTapToPay(isDeviceCapable)
        print("Device supports Tap to Pay: \(isDeviceCapable)")
        
        // If device is capable, check if Apple account is linked
        if isDeviceCapable {
            tapToPaySettings.isAppleAccountLinked { isLinked, error in
                print("Apple account linked for Tap to Pay: \(isLinked)")
                if let error = error {
                    print("Error checking Apple account linking: \(error.localizedDescription)")
                }
                
                // If not linked, we could prompt the user to link their account
                if !isLinked && error == nil {
                    print("Apple account needs to be linked for Tap to Pay")
                    // Could implement UI to prompt merchant to link account
                    // tapToPaySettings.linkAppleAccount { error in ... }
                }
            }
        }
    }
    
    /// Check if this device is capable of Tap to Pay
    func isDeviceCapable() -> Bool {
        guard let tapToPaySettings = self.tapToPaySettings else {
            return false
        }
        
        return tapToPaySettings.isDeviceCapable
    }
    
    /// Process a payment using Apple Tap to Pay on iPhone
    func processTapToPayPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        // Ensure SDK is initialized
        guard let _ = try? MobilePaymentsSDK.shared else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("Square SDK not initialized")
                completion(false, nil)
            }
            return
        }
        
        // Verify Tap to Pay is supported on this device
        guard let tapToPaySettings = self.tapToPaySettings, tapToPaySettings.isDeviceCapable else {
            DispatchQueue.main.async { [weak self] in
                self?.updatePaymentError("This device does not support Tap to Pay on iPhone")
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
        
        // Find view controller
        guard let presentedVC = getTopViewController() else {
            DispatchQueue.main.async { [weak self] in
                self?.updateIsProcessingPayment(false)
                self?.updatePaymentError("Unable to find view controller to present payment UI")
                completion(false, nil)
            }
            return
        }
        
        // Generate transaction ID
        let transactionId = "tap_\(Int(amount * 100))_\(Int(Date().timeIntervalSince1970))"
        
        // Get idempotency key
        let idempotencyKey = idempotencyKeyManager.getKey(for: transactionId)
        
        // Create TapToPayPaymentSource
        let tapToPaySource = TapToPayPaymentSource()
        
        // Validate the source is usable
        guard tapToPaySource.validate() else {
            DispatchQueue.main.async { [weak self] in
                self?.updateIsProcessingPayment(false)
                self?.updatePaymentError("Tap to Pay is not currently available")
                completion(false, nil)
            }
            return
        }
        
        // Create payment parameters with Tap to Pay source
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: Money(amount: amountInCents, currency: .USD),
            processingMode: .onlineOnly,
            source: tapToPaySource
        )
        
        // Create prompt parameters
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Create payment delegate
        let paymentDelegate = TapToPayPaymentDelegate(
            service: self,
            transactionId: transactionId,
            idempotencyManager: idempotencyKeyManager,
            completion: completion
        )
        
        // Start the payment with Tap to Pay
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
    
    /// Update supports Tap to Pay flag in payment service
    private func updateSupportsTapToPay(_ supports: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.supportsTapToPay = supports
            
            // Update overall payment methods availability if Tap to Pay is supported
            if supports, let paymentService = self?.paymentService {
                paymentService.hasAvailablePaymentMethods = true
            }
        }
    }
}

// MARK: - TapToPayPaymentDelegate
extension SquareTapToPayService {
    class TapToPayPaymentDelegate: NSObject, PaymentManagerDelegate {
        private weak var service: SquareTapToPayService?
        private let transactionId: String
        private let idempotencyManager: IdempotencyKeyManager
        private let completion: (Bool, String?) -> Void
        
        init(service: SquareTapToPayService,
             transactionId: String,
             idempotencyManager: IdempotencyKeyManager,
             completion: @escaping (Bool, String?) -> Void) {
            self.service = service
            self.transactionId = transactionId
            self.idempotencyManager = idempotencyManager
            self.completion = completion
            super.init()
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.service?.updateIsProcessingPayment(false)
                print("Tap to Pay payment successful with ID: \(String(describing: payment.id))")
                
                // Keep idempotency key for successful payments
                self.completion(true, payment.id)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.service?.updateIsProcessingPayment(false)
                
                // Handle different errors - focus on Tap to Pay specific errors
                let nsError = error as NSError
                
                // Check if this is a Tap to Pay specific error
                if let tapToPayError = error as? TapToPayReaderError {
                    switch tapToPayError {
                    case .notAvailable:
                        self.service?.updatePaymentError("Tap to Pay is not available right now. Please try again later.")
                    case .passcodeDisabled:
                        self.service?.updatePaymentError("Your device must have a passcode set to use Tap to Pay.")
                    case .unsupportedDeviceModel:
                        self.service?.updatePaymentError("This iPhone model does not support Tap to Pay.")
                    case .unsupportedOSVersion:
                        self.service?.updatePaymentError("Tap to Pay requires iOS 16.7 or later.")
                    case .banned:
                        self.service?.updatePaymentError("Your merchant account is not authorized for Tap to Pay.")
                    case .alreadyLinked, .linkingCanceled, .linkingFailed, .invalidToken:
                        self.service?.updatePaymentError("Issue with Apple account linking. Please try again.")
                    case .networkError, .noNetwork:
                        self.service?.updatePaymentError("Network connection issue. Please check your internet connection.")
                    case .notAuthorized:
                        self.service?.updatePaymentError("Not connected to Square. Please reconnect your account.")
                    case .other, .unexpected:
                        self.service?.updatePaymentError("An unexpected error occurred with Tap to Pay.")
                    @unknown default:
                        self.service?.updatePaymentError("Payment failed: \(error.localizedDescription)")
                    }
                } else if let paymentError = PaymentError(rawValue: nsError.code) {
                    // Handle standard payment errors
                    switch paymentError {
                    case .invalidPaymentSource:
                        self.service?.updatePaymentError("Tap to Pay source is invalid. Please try again.")
                    case .notAuthorized:
                        self.service?.updatePaymentError("Not connected to Square. Please reconnect your account.")
                    default:
                        self.service?.updatePaymentError("Payment failed: \(error.localizedDescription)")
                    }
                } else {
                    // Generic error handling
                    self.service?.updatePaymentError("Payment failed: \(error.localizedDescription)")
                }
                
                // Always remove the key for failed payments
                self.idempotencyManager.removeKey(for: self.transactionId)
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
                self.service?.updatePaymentError("Tap to Pay payment was canceled")
                print("Tap to Pay payment was canceled by user")
                self.completion(false, nil)
            }
        }
    }
}
