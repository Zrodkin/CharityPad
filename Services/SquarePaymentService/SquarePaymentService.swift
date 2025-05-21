import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

/// Enhanced payment service that uses Square catalog and orders
class UpdatedSquarePaymentService: NSObject, ObservableObject {
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
    private let readerConnectionService: SquareReaderConnectionService
    private let paymentProcessingService: SquarePaymentProcessingService
    private let permissionService: SquarePermissionService
    private let offlinePaymentService: SquareOfflinePaymentService
    private let catalogService: SquareCatalogService
    
    // MARK: - Private Properties
    
    private var readerService: SquareReaderService?
    private var paymentHandle: PaymentHandle?
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService, catalogService: SquareCatalogService) {
        self.authService = authService
        self.catalogService = catalogService
        
        // Initialize services
        self.sdkInitializationService = SquareSDKInitializationService()
        self.readerConnectionService = SquareReaderConnectionService()
        self.paymentProcessingService = SquarePaymentProcessingService()
        self.permissionService = SquarePermissionService()
        self.offlinePaymentService = SquareOfflinePaymentService()
        
        super.init()
        
        // Configure services with dependencies
        self.sdkInitializationService.configure(with: authService, paymentService: self)
        self.permissionService.configure(with: self)
        self.readerConnectionService.configure(with: self, permissionService: permissionService)
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
    
    /// Process a payment using Square catalog and orders
    func processPayment(amount: Double,
                        isCustomAmount: Bool = false,
                        catalogItemId: String? = nil,
                        completion: @escaping (Bool, String?) -> Void) {
        
        // Ensure we're authenticated
        guard authService.isAuthenticated else {
            paymentError = "Not connected to Square"
            completion(false, nil)
            return
        }
        
        // Ensure SDK is initialized
        guard isSDKAuthorized() else {
            initializeSDK()
            paymentError = "Square SDK not authorized yet"
            completion(false, nil)
            return
        }
        
        // Ensure reader is connected
        guard isReaderConnected else {
            paymentError = "Card reader not connected"
            completion(false, nil)
            return
        }
        
        // Set processing state
        isProcessingPayment = true
        paymentError = nil
        
        // Clear any previous order ID
        currentOrderId = nil
        
        // Step 1: Create an order for this donation
        createOrder(amount: amount, isCustomAmount: isCustomAmount, catalogItemId: catalogItemId) { [weak self] orderId, error in
            guard let self = self else { return }
            
            if let error = error {
                self.handlePaymentError(error)
                completion(false, nil)
                return
            }
            
            guard let orderId = orderId else {
                self.handlePaymentError(NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "No order ID returned"]))
                completion(false, nil)
                return
            }
            
            self.currentOrderId = orderId
            
            // Step 2: Process payment for this order
            self.processOrderPayment(orderId: orderId, amount: amount, completion: completion)
        }
    }
    
    /// Create an order for a donation
    private func createOrder(amount: Double,
                           isCustomAmount: Bool,
                           catalogItemId: String?,
                           completion: @escaping (String?, Error?) -> Void) {
        // Create line item for the order
        var lineItem: [String: Any]
        
        if isCustomAmount || catalogItemId == nil {
            // For custom amounts, use ad-hoc line item
            lineItem = [
                "name": "Custom Donation",
                "quantity": "1",
                "base_price_money": [
                    "amount": Int(amount * 100), // Convert to cents
                    "currency": "USD"
                ]
            ]
        } else {
            // For preset amounts, use catalog reference
            lineItem = [
                "catalog_object_id": catalogItemId!,
                "quantity": "1"
            ]
        }
        
        // Create request body
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "line_items": [lineItem],
            "note": "Donation via CharityPad"
        ]
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/orders/create") else {
            completion(nil, NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(nil, error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                guard let data = data else {
                    completion(nil, NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "No data returned"]))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: error]))
                        } else if let orderId = json["order_id"] as? String {
                            completion(orderId, nil)
                        } else {
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse order ID"]))
                        }
                    } else {
                        completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]))
                    }
                } catch {
                    completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(error.localizedDescription)"]))
                }
            }
        }.resume()
    }
    
    /// Process payment for an order using Square Mobile Payments SDK
    private func processOrderPayment(orderId: String, amount: Double, completion: @escaping (Bool, String?) -> Void) {
        guard isSDKAuthorized() else {
            handlePaymentError(NSError(domain: "com.charitypad", code: 401, userInfo: [NSLocalizedDescriptionKey: "SDK not authorized"]))
            completion(false, nil)
            return
        }
        
        // Find the top view controller to present the payment UI
        guard let presentedVC = getTopViewController() else {
            handlePaymentError(NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to present payment UI"]))
            completion(false, nil)
            return
        }
        
        // Generate a unique idempotency key for this payment
        let idempotencyKey = UUID().uuidString
        
        // Create payment parameters with order ID
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: Money(amount: UInt(amount * 100), currency: .USD),
            orderId: orderId,
            processingMode: supportsOfflinePayments ? .autoDetect : .onlineOnly
        )
        
        // Create prompt parameters
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Start the payment
        paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParameters,
            promptParameters: promptParameters,
            from: presentedVC,
            delegate: self
        )
        
        // Store the completion handler for later use
        self.paymentCompletionHandler = completion
    }
    
    // MARK: - Private Properties and Methods
    
    // Store the completion handler for async payment processing
    private var paymentCompletionHandler: ((Bool, String?) -> Void)?
    
    /// Handle payment errors
    private func handlePaymentError(_ error: Error) {
        isProcessingPayment = false
        paymentError = error.localizedDescription
        print("Payment error: \(error.localizedDescription)")
    }
    
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
        readerConnectionService.connectToReader()
    }
    
    /// Set the reader service
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
        self.readerConnectionService.setReaderService(readerService)
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

extension UpdatedSquarePaymentService: PaymentManagerDelegate {
    
    func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Reset processing state
            self.isProcessingPayment = false
            self.paymentError = nil
            
            print("Payment successful with ID: \(String(describing: payment.id))")
            
            // Call completion handler
            self.paymentCompletionHandler?(true, payment.id)
            self.paymentCompletionHandler = nil
        }
    }
    
    func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle payment failure
            self.isProcessingPayment = false
            self.paymentError = "Payment failed: \(error.localizedDescription)"
            
            print("Payment failed: \(error.localizedDescription)")
            
            // Call completion handler
            self.paymentCompletionHandler?(false, nil)
            self.paymentCompletionHandler = nil
        }
    }
    
    func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Handle payment cancellation
            self.isProcessingPayment = false
            self.paymentError = "Payment was canceled"
            
            print("Payment was canceled by user")
            
            // Call completion handler
            self.paymentCompletionHandler?(false, nil)
            self.paymentCompletionHandler = nil
        }
    }
}riptionKey: "Unable to parse order ID"]))
                        }
                    } else {
                        completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDesc
