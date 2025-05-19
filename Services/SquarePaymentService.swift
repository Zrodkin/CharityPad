import Foundation
import SwiftUI
import SquareMobilePaymentsSDK
import CoreLocation
import CoreBluetooth

/// Service for handling Square payments
class SquarePaymentService: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var isProcessingPayment = false
    @Published var paymentError: String? = nil
    @Published var isReaderConnected = false
    @Published var connectionStatus: String = "Disconnected"
    
    // MARK: - Private Properties
    
    private let authService: SquareAuthService
    private var paymentHandle: PaymentHandle?
    private lazy var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var readerService: SquareReaderService?
    private let idempotencyKeyManager = IdempotencyKeyManager()
    private var isInitialized = false
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService) {
        self.authService = authService
        super.init()
        
        // Setup location manager
        locationManager.delegate = self
        
        // Don't add SDK observers in init - we'll do this when needed
        
        // Register for authentication success notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAuthenticationSuccess(_:)),
            name: .squareAuthenticationSuccessful,
            object: nil
        )
    }
    
    deinit {
        // Only remove observer if we added it previously
        if isInitialized {
            MobilePaymentsSDK.shared.authorizationManager.remove(self)
        }
        
        // Remove notification observer
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Check if SDK is initialized and fully ready
    func checkIfInitialized() -> Bool {
        // First make sure the shared instance is available
        guard let _ = try? MobilePaymentsSDK.shared else {
            print("Square SDK not initialized yet - shared instance not available")
            return false
        }
        
        // Mark as initialized if we get here
        if !isInitialized {
            isInitialized = true
            
            // Now we can register as an observer
            MobilePaymentsSDK.shared.authorizationManager.add(self)
            
            print("Square SDK initialized and available")
        }
        
        return true
    }
    
    /// Set the reader service - called after initialization
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
    }
    
    /// Debug function to explore Square SDK
    func debugSquareSDK() {
        // Don't proceed if not initialized
        guard checkIfInitialized() else {
            print("Cannot debug Square SDK - not yet initialized")
            return
        }
        
        print("\n--- Square SDK Debug Information ---")
        
        // SDK version and environment
        print("SDK Version: \(MobilePaymentsSDK.version)")
        print("SDK Environment: \(String(describing: MobilePaymentsSDK.shared.settingsManager.sdkSettings.environment))")
        
        // Authorization state
        print("Authorization State: \(String(describing: MobilePaymentsSDK.shared.authorizationManager.state))")
        
        // Prompt parameters exploration
        print("\n--- Prompt Parameters ---")
        let promptParams = PromptParameters(mode: .default, additionalMethods: .all)
        print("Successfully created PromptParameters")
        print("- mode: \(String(describing: promptParams.mode))")
        print("- additionalMethods: \(String(describing: promptParams.additionalMethods))")
        
        // Payment parameters
        print("\n--- Payment Parameters ---")
        let paymentParams = PaymentParameters(
            idempotencyKey: UUID().uuidString,
            amountMoney: Money(amount: 100, currency: .USD),
            processingMode: .onlineOnly
        )
        print("Successfully created PaymentParameters")
        print("- idempotencyKey: \(paymentParams.idempotencyKey)")
        print("- amountMoney: \(paymentParams.amountMoney.amount) \(paymentParams.amountMoney.currency)")
        print("- processingMode: \(String(describing: paymentParams.processingMode))")
        
        print("\n--- Debug Complete ---")
    }
    
    /// Initialize the Square SDK
    func initializeSDK() {
        // Check if SDK is available first
        guard checkIfInitialized() else {
            connectionStatus = "SDK not initialized"
            return
        }
        
        // NEW: Use locationId instead of merchantId
        guard let accessToken = authService.accessToken,
              let locationID = authService.locationId else {
            
            // Fallback to merchantId if locationId is not available (not recommended)
            if let accessToken = authService.accessToken,
               let fallbackID = authService.merchantId {
                paymentError = "No location ID available, using merchant ID as fallback"
                connectionStatus = "Using fallback ID"
                print("WARNING: Using merchant ID as fallback for location ID. This might not work correctly.")
                
                // Continue with merchantId as fallback
                authorizeSDK(accessToken: accessToken, locationID: fallbackID)
                return
            }
            
            paymentError = "No access token or location ID available"
            connectionStatus = "Missing credentials"
            return
        }
        
        // Check if already authorized
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            print("Square SDK already authorized")
            self.connectionStatus = "SDK already authorized"
            updateConnectionStatus()
            return
        }
        
        // Request necessary permissions
        requestLocationPermission()
        requestBluetoothPermissions()
        
        #if DEBUG
        // Run debug in debug builds
        debugSquareSDK()
        #endif
        
        // Authorize the SDK with locationID (not merchant ID)
        print("Authorizing Square SDK with access token and location ID: \(locationID)")
        MobilePaymentsSDK.shared.authorizationManager.authorize(
            withAccessToken: accessToken,
            locationID: locationID
        ) { error in
            DispatchQueue.main.async {
                if let authError = error {
                    self.paymentError = "Authorization error: \(authError.localizedDescription)"
                    self.connectionStatus = "Authorization failed"
                    print("Square SDK authorization error: \(authError.localizedDescription)")
                    return
                }
                
                self.connectionStatus = "SDK authorized"
                print("Square Mobile Payments SDK successfully authorized.")
                
                // Update connection status and start looking for readers
                self.updateConnectionStatus()
                self.connectToReader()
            }
        }
    }
    
    /// Check if the Square SDK is currently authorized
    func isSDKAuthorized() -> Bool {
        // Make sure initialized first
        guard checkIfInitialized() else { return false }
        
        return MobilePaymentsSDK.shared.authorizationManager.state == .authorized
    }
    
    /// Deauthorize the Square SDK
    /// - Parameter completion: Optional callback after deauthorization completes
    func deauthorizeSDK(completion: @escaping () -> Void = {}) {
        // Make sure initialized first
        guard checkIfInitialized() else {
            completion()
            return
        }
        
        MobilePaymentsSDK.shared.authorizationManager.deauthorize {
            DispatchQueue.main.async {
                self.connectionStatus = "Disconnected"
                self.isReaderConnected = false
                completion()
            }
        }
    }
    
    /// Connect to a Square reader
    func connectToReader() {
        // Make sure SDK is initialized
        guard checkIfInitialized() else { return }
        
        // Ensure SDK is initialized and authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            if let accessToken = authService.accessToken,
               let locationID = authService.merchantId {
                authorizeSDK(accessToken: accessToken, locationID: locationID)
            } else {
                initializeSDK()
            }
            return
        }
        
        // Check if Bluetooth is enabled
        if let centralManager = centralManager, centralManager.state != .poweredOn {
            DispatchQueue.main.async {
                self.paymentError = "Bluetooth is required for connecting to readers"
                self.connectionStatus = "Bluetooth required"
            }
            return
        }
        
        // Check if location permission is granted
        let authStatus = locationManager.authorizationStatus
        if authStatus != .authorizedWhenInUse && authStatus != .authorizedAlways {
            DispatchQueue.main.async {
                self.paymentError = "Location permission is required for connecting to readers"
                self.connectionStatus = "Location access needed"
            }
            return
        }
        
        // Use reader service to find available readers
        if let readerService = readerService {
            if readerService.readers.isEmpty {
                // No readers - start pairing if not in progress
                guard checkIfInitialized() else { return }
                
                if !MobilePaymentsSDK.shared.readerManager.isPairingInProgress {
                    DispatchQueue.main.async {
                        self.connectionStatus = "No readers found. Starting pairing..."
                    }
                    readerService.startPairing()
                } else {
                    DispatchQueue.main.async {
                        self.connectionStatus = "Searching for readers..."
                    }
                }
                return
            }
            
            // If we have a ready reader, select it
            if let readyReader = readerService.readers.first(where: { $0.state == .ready }) {
                readerService.selectReader(readyReader)
                DispatchQueue.main.async {
                    self.connectionStatus = "Connected to \(readyReader.model == .stand ? "Square Stand" : "Square Reader")"
                    self.isReaderConnected = true
                    self.paymentError = nil
                }
                return
            }
            
            // If we have a selected reader that's not ready, show status
            if let selectedReader = readerService.selectedReader, selectedReader.state != .ready {
                DispatchQueue.main.async {
                    self.connectionStatus = "Reader \(readerService.readerStateDescription(selectedReader.state))"
                    self.isReaderConnected = false
                }
                return
            }
            
            // If we have readers but none are ready
            DispatchQueue.main.async {
                self.connectionStatus = "Reader not ready. Please check reader status."
                self.isReaderConnected = false
            }
            return
        }
        
        // Fallback if reader service isn't available but SDK is authorized
        guard checkIfInitialized() else { return }
        
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            DispatchQueue.main.async {
                self.connectionStatus = "Ready to accept payment"
                self.isReaderConnected = true
            }
        }
    }
    
    /// Process a payment
    func processPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        // Ensure SDK is initialized
        guard checkIfInitialized() else {
            DispatchQueue.main.async {
                self.paymentError = "Square SDK not initialized"
                completion(false, nil)
            }
            return
        }
        
        // Verify authentication
        guard authService.isAuthenticated else {
            DispatchQueue.main.async {
                self.paymentError = "Not authenticated with Square"
                completion(false, nil)
            }
            return
        }
        
        // Ensure SDK is authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            DispatchQueue.main.async {
                self.initializeSDK()
                completion(false, nil)
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessingPayment = true
            self.paymentError = nil
        }
        
        // Calculate amount in cents
        let amountInCents = UInt(amount * 100)
        
        // Find the view controller to present the payment UI
        guard let presentedVC = getTopViewController() else {
            DispatchQueue.main.async {
                self.isProcessingPayment = false
                self.paymentError = "Unable to find view controller to present payment UI"
                completion(false, nil)
            }
            return
        }
        
        // Generate a transaction ID based on amount and timestamp
        let transactionId = "txn_\(Int(amount * 100))_\(Int(Date().timeIntervalSince1970))"
        
        // Get or create idempotency key for this transaction
        let idempotencyKey = idempotencyKeyManager.getKey(for: transactionId)
        
        // Create payment parameters
        let paymentParameters = PaymentParameters(
            idempotencyKey: idempotencyKey,
            amountMoney: Money(amount: amountInCents, currency: .USD),
            processingMode: .onlineOnly
        )
        
        // Create prompt parameters (using documented parameters)
        let promptParameters = PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        // Create payment delegate
        let paymentDelegate = PaymentDelegate(
            service: self,
            transactionId: transactionId,
            idempotencyManager: idempotencyKeyManager,
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
    
    @objc private func handleAuthenticationSuccess(_ notification: Notification) {
        // Extract credentials if needed
        if let userInfo = notification.userInfo,
           let accessToken = userInfo["accessToken"] as? String,
           let merchantId = userInfo["merchantId"] as? String {
            print("Received authentication success notification with merchant ID: \(merchantId)")
        }
        
        // Initialize SDK after successful authentication
        DispatchQueue.main.async {
            self.initializeSDK()
        }
    }
    
    /// Authorize the Mobile Payments SDK
    private func authorizeSDK(accessToken: String, locationID: String) {
        // Make sure initialized first
        guard checkIfInitialized() else { return }
        
        // Check if already authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized else {
            DispatchQueue.main.async {
                self.connectionStatus = "SDK already authorized"
                self.updateConnectionStatus()
            }
            return
        }
        
        // Authorize with Square
        MobilePaymentsSDK.shared.authorizationManager.authorize(
            withAccessToken: accessToken,
            locationID: locationID
        ) { error in
            DispatchQueue.main.async {
                if let authError = error {
                    self.paymentError = "Authorization error: \(authError.localizedDescription)"
                    self.connectionStatus = "Authorization failed"
                    print("Square SDK authorization error: \(authError.localizedDescription)")
                    return
                }
                
                self.connectionStatus = "SDK authorized"
                print("Square Mobile Payments SDK successfully authorized.")
                
                // Update connection status
                self.updateConnectionStatus()
            }
        }
    }
    
    /// Request location permission
    private func requestLocationPermission() {
        let authorizationStatus = locationManager.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            paymentError = "Location permission is required for payments"
            print("Location permission denied - direct user to Settings app")
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location services already authorized")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    /// Request Bluetooth permissions
    private func requestBluetoothPermissions() {
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        } else if centralManager?.state == .poweredOn {
            print("Bluetooth is already powered on")
        }
    }
    
    /// Update connection status based on reader state
    private func updateConnectionStatus() {
        // Make sure SDK is initialized
        guard checkIfInitialized() else { return }
        
        if let readerService = readerService {
            if readerService.readers.isEmpty {
                DispatchQueue.main.async {
                    self.connectionStatus = "No readers connected"
                    self.isReaderConnected = false
                }
                return
            }
            
            if let readyReader = readerService.readers.first(where: { $0.state == .ready }) {
                DispatchQueue.main.async {
                    self.connectionStatus = "Connected to \(readyReader.model == .stand ? "Square Stand" : "Square Reader")"
                    self.isReaderConnected = true
                }
                return
            }
            
            // We have readers but none are ready
            if let firstReader = readerService.readers.first {
                DispatchQueue.main.async {
                    self.connectionStatus = "Reader \(readerService.readerStateDescription(firstReader.state))"
                    self.isReaderConnected = false
                }
            }
        } else {
            // Fallback if we don't have reader service
            if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
                DispatchQueue.main.async {
                    self.connectionStatus = "SDK authorized, ready for payment"
                    self.isReaderConnected = true
                }
            } else {
                DispatchQueue.main.async {
                    self.connectionStatus = "Not connected to Square"
                    self.isReaderConnected = false
                }
            }
        }
    }
    
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
}

// MARK: - AuthorizationStateObserver
extension SquarePaymentService: AuthorizationStateObserver {
    func authorizationStateDidChange(_ authorizationState: AuthorizationState) {
        DispatchQueue.main.async {
            if authorizationState == .authorized {
                self.connectionStatus = "SDK authorized"
                self.connectToReader()
            } else {
                self.connectionStatus = "Not authorized"
                self.isReaderConnected = false
            }
        }
    }
}

// MARK: - LocationManagerDelegate
extension SquarePaymentService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location permission granted")
            // Try to authorize SDK if we have credentials
            if let accessToken = authService.accessToken,
               let locationID = authService.merchantId {
                authorizeSDK(accessToken: accessToken, locationID: locationID)
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.paymentError = "Location permission is required for Square payments"
                self.connectionStatus = "Location access denied"
            }
        case .notDetermined:
            print("Location permission not determined yet")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension SquarePaymentService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on and ready for use")
            // Try to connect to reader if SDK is authorized
            if checkIfInitialized(), MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
                self.connectToReader()
            }
        case .poweredOff:
            DispatchQueue.main.async {
                self.paymentError = "Bluetooth is powered off. Please turn it on to use card readers."
                self.isReaderConnected = false
                self.connectionStatus = "Bluetooth turned off"
            }
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            DispatchQueue.main.async {
                self.paymentError = "Bluetooth permission is required for card readers"
                self.isReaderConnected = false
                self.connectionStatus = "Bluetooth permission denied"
            }
        case .unsupported:
            DispatchQueue.main.async {
                self.paymentError = "This device does not support Bluetooth"
                self.isReaderConnected = false
                self.connectionStatus = "Bluetooth not supported"
            }
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
}

// MARK: - Payment Delegate
extension SquarePaymentService {
    class PaymentDelegate: NSObject, PaymentManagerDelegate {
        private weak var service: SquarePaymentService?
        private let transactionId: String
        private let idempotencyManager: IdempotencyKeyManager
        private let completion: (Bool, String?) -> Void
        
        init(service: SquarePaymentService,
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
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                print("Payment successful with ID: \(String(describing: payment.id))")
                
                // Keep idempotency key for successful payments
                
                self.completion(true, payment.id)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
            DispatchQueue.main.async {
                // Handle specific payment errors differently
                let nsError = error as NSError
                if let paymentError = PaymentError(rawValue: nsError.code) {
                    switch paymentError {
                    case .idempotencyKeyReused:
                        // This indicates a duplicate payment attempt, do not delete the key
                        print("Idempotency key reused - likely duplicate transaction attempt")
                    default:
                        // For other errors, remove the idempotency key to allow retries
                        self.idempotencyManager.removeKey(for: self.transactionId)
                    }
                } else {
                    // Unknown error type, remove key to be safe
                    self.idempotencyManager.removeKey(for: self.transactionId)
                }
                
                self.service?.isProcessingPayment = false
                self.service?.paymentError = error.localizedDescription
                print("Payment failed: \(error.localizedDescription)")
                self.completion(false, nil)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
            DispatchQueue.main.async {
                // Remove idempotency key for canceled payments
                self.idempotencyManager.removeKey(for: self.transactionId)
                
                self.service?.isProcessingPayment = false
                self.service?.paymentError = "Payment was canceled"
                print("Payment was canceled by user")
                self.completion(false, nil)
            }
        }
    }
}

// MARK: - IdempotencyKeyManager
/// Manages idempotency keys for payments to prevent duplicate charges
class IdempotencyKeyManager {
    private let userDefaultsKey = "IdempotencyKeys"
    private var storage: [String: String] = [:]
    
    init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            storage = stored
        }
    }
    
    func getKey(for transactionId: String) -> String {
        if let existingKey = storage[transactionId] {
            return existingKey
        }
        
        let newKey = UUID().uuidString
        storage[transactionId] = newKey
        saveStorage()
        return newKey
    }
    
    func removeKey(for transactionId: String) {
        storage.removeValue(forKey: transactionId)
        saveStorage()
    }
    
    private func saveStorage() {
        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
