import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

/// Enhanced payment service that uses Square catalog and orders
class SquarePaymentService: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var isProcessingPayment = false
    @Published var paymentError: String? = nil
    @Published var isReaderConnected = false
    @Published var connectionStatus: String = "Disconnected"
    
    // Payment methods support flags
    @Published var supportsContactless = false
    @Published var supportsChip = false
    @Published var supportsSwipe = false
    @Published var supportsOfflinePayments = false
    @Published var hasAvailablePaymentMethods = false
    @Published var offlinePendingCount = 0
    
    // Order tracking
    @Published var currentOrderId: String? = nil
    
    // MARK: - Services
    
    private let authService: SquareAuthService
    private let sdkInitializationService: SquareSDKInitializationService
    private let paymentProcessingService: SquarePaymentProcessingService
    private let permissionService: SquarePermissionService
    private let offlinePaymentService: SquareOfflinePaymentService
    private let catalogService: SquareCatalogService
    
    // MARK: - Private Properties
    
    private var readerService: SquareReaderService?
    private var paymentHandle: PaymentHandle?
    private let idempotencyKeyManager = IdempotencyKeyManager()
    
    // Completion handlers for different flows
    private var mainPaymentCompletion: ((Bool, String?) -> Void)?
    private var currentProcessingMode: InternalProcessingMode = .direct
    
    // Processing modes - renamed to avoid conflict with Square SDK's ProcessingMode
    private enum InternalProcessingMode {
        case direct          // Direct SDK payment (current working approach)
        case orderBased     // Order creation + backend processing (future enhancement)
    }
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService, catalogService: SquareCatalogService) {
        self.authService = authService
        self.catalogService = catalogService
        
        // Initialize services
        self.sdkInitializationService = SquareSDKInitializationService()
        self.paymentProcessingService = SquarePaymentProcessingService()
        self.permissionService = SquarePermissionService()
        self.offlinePaymentService = SquareOfflinePaymentService()
        
        super.init()
        
        // Configure services with dependencies
        self.sdkInitializationService.configure(with: authService, paymentService: self)
        self.permissionService.configure(with: self)
        self.paymentProcessingService.configure(with: self, authService: authService)
        self.offlinePaymentService.configure(with: self)
        
        // Register for authentication success notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthenticationSuccess(_:)),
            name: .squareAuthenticationSuccessful,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Check if the SDK is authorized
    func isSDKAuthorized() -> Bool {
        return sdkInitializationService.isSDKAuthorized()
    }
    
    /// Initialize the Square SDK
    func initializeSDK() {
        sdkInitializationService.initializeSDK()
    }
    
    /// Connect to a Square reader
    func connectToReader() {
        // Use the injected reader service if available
        readerService?.connectToReader()
    }
    
    /// Set the reader service and configure it
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
        // Configure the reader service with this payment service and permission service
        readerService.configure(with: self, permissionService: permissionService)
    }
    
    /// Deauthorize the Square SDK
    func deauthorizeSDK(completion: @escaping () -> Void = {}) {
        sdkInitializationService.deauthorizeSDK(completion: completion)
    }
    
    /// Process payment (updated to match CheckoutView expectations)
    func processPayment(
        amount: Double,
        isCustomAmount: Bool = false,
        catalogItemId: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        print("⚠️ Using legacy direct payment flow. Consider using processPaymentWithOrder for better itemization.")
        
        // Ensure SDK is initialized
        guard let _ = try? MobilePaymentsSDK.shared else {
            DispatchQueue.main.async { [weak self] in
                self?.paymentError = "Square SDK not initialized"
                completion(false, nil)
            }
            return
        }
        
        // Verify authentication
        guard authService.isAuthenticated else {
            DispatchQueue.main.async { [weak self] in
                self?.paymentError = "Not authenticated with Square"
                completion(false, nil)
            }
            return
        }
        
        // Ensure SDK is authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            DispatchQueue.main.async { [weak self] in
                self?.initializeSDK()
                self?.paymentError = "SDK not authorized"
                completion(false, nil)
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isProcessingPayment = true
            self?.paymentError = nil
        }
        
        // Calculate amount in cents
        let amountInCents = UInt(amount * 100)
        
        // Find the view controller to present the payment UI
        guard let presentedVC = getTopViewController() else {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessingPayment = false
                self?.paymentError = "Unable to find view controller to present payment UI"
                completion(false, nil)
            }
            return
        }
        
        // Generate a transaction ID based on amount and timestamp
        let transactionId = "txn_\(Int(amount * 100))_\(Int(Date().timeIntervalSince1970))"
        
        // Get or create idempotency key for this transaction
        let idempotencyKey = idempotencyKeyManager.getKey(for: transactionId) ?? {
            let newKey = UUID().uuidString
            idempotencyKeyManager.store(id: transactionId, idempotencyKey: newKey)
            return newKey
        }()
        
        // Create Money object (which conforms to MoneyAmount protocol)
        let moneyAmount = Money(amount: amountInCents, currency: .USD)
        
        // Create payment parameters with correct types - using Square SDK's ProcessingMode
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: moneyAmount,
            processingMode: supportsOfflinePayments ? ProcessingMode.autoDetect : ProcessingMode.onlineOnly
        )
        
        // Create prompt parameters
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Store completion for delegate
        mainPaymentCompletion = completion
        
        // Start the payment
        paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParameters,
            promptParameters: promptParameters,
            from: presentedVC,
            delegate: self
        )
    }
    
    // MARK: - Private Methods
    
    /// Get the top view controller to present payment UI
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
    
    /// Process notifications
    @objc private func handleAuthenticationSuccess(_ notification: Notification) {
        // Initialize SDK after successful authentication
        DispatchQueue.main.async {
            self.initializeSDK()
        }
    }
}

// MARK: - PaymentManagerDelegate Implementation

extension SquarePaymentService: PaymentManagerDelegate {
    
    func paymentManager(_ paymentManager: PaymentManager, didStart payment: Payment) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("Payment started with ID: \(String(describing: payment.id))")
            
            // Update UI to show payment has started
            self.isProcessingPayment = true
            self.paymentError = nil
            
            // Update the connection status
            self.connectionStatus = "Processing payment..."
        }
    }
    
    func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Reset processing state
            self.isProcessingPayment = false
            self.paymentError = nil
            self.connectionStatus = "Payment completed"
            
            print("Payment successful with ID: \(String(describing: payment.id))")
            
            // For successful payments, keep the idempotency key (don't remove it)
            // This prevents duplicate charges if the same payment is attempted again
            
            // Handle completion
            self.mainPaymentCompletion?(true, payment.id)
            self.mainPaymentCompletion = nil
        }
    }
    
    func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle payment failure
            self.isProcessingPayment = false
            self.paymentError = "Payment failed: \(error.localizedDescription)"
            self.connectionStatus = "Payment failed"
            
            print("Payment failed: \(error.localizedDescription)")
            
            // Enhanced error handling based on your SquarePaymentProcessingService
            let nsError = error as NSError
            
            // Check if this is a retryable error or should remove idempotency key
            var shouldRemoveKey = true
            
            if let paymentError = PaymentError(rawValue: nsError.code) {
                switch paymentError {
                case .idempotencyKeyReused:
                    // Don't remove key for duplicate payment attempts
                    shouldRemoveKey = false
                    
                case .noNetwork:
                    // Keep key if offline payments are supported
                    shouldRemoveKey = !self.supportsOfflinePayments
                    
                case .paymentAlreadyInProgress:
                    // Don't remove key since payment is still in progress
                    shouldRemoveKey = false
                    
                case .timedOut:
                    // Remove key for timeout so user can retry
                    shouldRemoveKey = true
                    
                default:
                    // Remove key for most other errors
                    shouldRemoveKey = true
                }
            }
            
            // Note: We can't easily access the transaction ID here, so we'll let the
            // calling code handle idempotency key cleanup based on the error type
            
            // Handle completion
            self.mainPaymentCompletion?(false, nil)
            self.mainPaymentCompletion = nil
        }
    }
    
    func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle payment cancellation
            self.isProcessingPayment = false
            self.paymentError = "Payment was canceled"
            self.connectionStatus = "Payment canceled"
            
            print("Payment was canceled by user")
            
            // For cancelled payments, we should remove the idempotency key
            // so the user can try again with the same amount
            // Note: The calling code should handle this cleanup
            
            // Handle completion
            self.mainPaymentCompletion?(false, nil)
            self.mainPaymentCompletion = nil
        }
    }
}

// MARK: - Order-Based Payment Processing Extension

extension SquarePaymentService {
    
    /// NEW: Process payment with order integration (recommended flow)
    func processPaymentWithOrder(
        amount: Double,
        orderId: String,
        allowOffline: Bool = true,
        completion: @escaping (Bool, String?) -> Void
    ) {
        print("🚀 Starting order-based payment processing")
        print("💰 Amount: $\(amount)")
        print("🛒 Order ID: \(orderId)")
        
        // Ensure SDK is initialized
        guard let _ = try? MobilePaymentsSDK.shared else {
            DispatchQueue.main.async { [weak self] in
                self?.paymentError = "Square SDK not initialized"
                completion(false, nil)
            }
            return
        }
        
        // Verify authentication
        guard authService.isAuthenticated else {
            DispatchQueue.main.async { [weak self] in
                self?.paymentError = "Not authenticated with Square"
                completion(false, nil)
            }
            return
        }
        
        // Ensure SDK is authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            DispatchQueue.main.async { [weak self] in
                self?.initializeSDK()
                self?.paymentError = "SDK not authorized"
                completion(false, nil)
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isProcessingPayment = true
            self?.paymentError = nil
            self?.currentOrderId = orderId
        }
        
        // Calculate amount in cents
        let amountInCents = UInt(amount * 100)
        
        // Find the view controller to present the payment UI
        guard let presentedVC = getTopViewController() else {
            DispatchQueue.main.async { [weak self] in
                self?.isProcessingPayment = false
                self?.paymentError = "Unable to find view controller to present payment UI"
                completion(false, nil)
            }
            return
        }
        
        // Generate a transaction ID based on order ID and timestamp
        let transactionId = "txn_\(String(orderId.suffix(8)))_\(Int(Date().timeIntervalSince1970))"
        
        // Get or create idempotency key for this transaction
        let idempotencyKey = idempotencyKeyManager.getKey(for: transactionId) ?? {
            let newKey = UUID().uuidString
            idempotencyKeyManager.store(id: transactionId, idempotencyKey: newKey)
            return newKey
        }()
        
        // Determine the processing mode based on offline support - using Square SDK's ProcessingMode
        let processingMode: ProcessingMode
        if allowOffline && supportsOfflinePayments {
            processingMode = .autoDetect  // Will try online, fall back to offline if needed
        } else {
            processingMode = .onlineOnly  // Only process payments online
        }
        
        // Create Money object (which conforms to MoneyAmount protocol)
        let moneyAmount = Money(amount: amountInCents, currency: .USD)
        
        // ✨ KEY ENHANCEMENT: Create payment parameters with ORDER ID
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: moneyAmount,
            processingMode: processingMode
        )
        
        // 🎯 THIS IS THE CRITICAL ADDITION: Set the order ID
        paymentParameters.orderID = orderId
        
        // Optional: Add reference ID for tracking
        paymentParameters.referenceID = "donation_\(transactionId)"
        
        // Optional: Add note for clarity
        paymentParameters.note = "Donation via CharityPad"
        
        print("📋 Payment Parameters:")
        print("   💳 Amount: \(amountInCents) cents")
        print("   🛒 Order ID: \(orderId)")
        print("   🔑 Idempotency Key: \(idempotencyKey)")
        print("   📱 Processing Mode: \(processingMode)")
        
        // Create prompt parameters
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Store completion for delegate
        mainPaymentCompletion = completion
        
        // Start the payment with order integration
        print("🚀 Starting Square payment with order integration...")
        paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParameters,
            promptParameters: promptParameters,
            from: presentedVC,
            delegate: self  // Use existing delegate
        )
    }
    
    // MARK: - Helper Methods for Order Integration
    
    /// Handle successful payment completion
    private func handlePaymentSuccess(transactionId: String, paymentId: String?) {
        // Keep idempotency key for successful payments (don't remove)
        // This helps prevent duplicate payments if the same transaction is attempted again
        print("✅ Payment successful, keeping idempotency key for transaction: \(transactionId)")
    }
    
    /// Handle failed payment
    private func handlePaymentFailure(transactionId: String, shouldRetry: Bool = true) {
        if shouldRetry {
            // For retryable failures, keep the idempotency key
            print("⚠️ Payment failed but retryable, keeping idempotency key for transaction: \(transactionId)")
        } else {
            // For non-retryable failures, remove the idempotency key
            idempotencyKeyManager.removeKey(for: transactionId)
            print("❌ Payment failed permanently, removed idempotency key for transaction: \(transactionId)")
        }
    }
    
    /// Handle cancelled payment
    private func handlePaymentCancellation(transactionId: String) {
        // Remove idempotency key for cancelled payments so user can try again
        idempotencyKeyManager.removeKey(for: transactionId)
        print("🚫 Payment cancelled, removed idempotency key for transaction: \(transactionId)")
    }
}
