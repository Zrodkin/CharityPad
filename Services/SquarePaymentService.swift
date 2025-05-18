import Foundation
import SwiftUI
import SquareMobilePaymentsSDK
import CoreLocation
import CoreBluetooth

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
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService) {
        self.authService = authService
        super.init()
        
        // Setup location manager
        locationManager.delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Set the reader service - called after initialization
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
    }
    
    /// Initialize the Square SDK
    func initializeSDK() {
        guard let accessToken = authService.accessToken,
              let locationID = authService.merchantId else {
            paymentError = "No access token or location ID available"
            return
        }
        
        // Request necessary permissions
        requestLocationPermission()
        requestBluetoothPermissions()
        
        // Authorize the SDK
        authorizeSDK(accessToken: accessToken, locationID: locationID)
    }
    
    /// Connect to a Square reader
    func connectToReader() {
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
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            DispatchQueue.main.async {
                self.connectionStatus = "Ready to accept payment"
                self.isReaderConnected = true
            }
        }
    }
    
    /// Process a payment
    func processPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        // Verify authentication
        guard authService.isAuthenticated else {
            DispatchQueue.main.async {
                self.paymentError = "Not authenticated with Square"
                completion(false, nil)
            }
            return
        }
        
        // Ensure SDK is initialized
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
        
        // Get available card input methods
        let availableInputMethods = readerService?.availableCardInputMethods ??
                                    MobilePaymentsSDK.shared.paymentManager.availableCardInputMethods
        
        // Create payment parameters
        let paymentParameters = PaymentParameters(
            idempotencyKey: UUID().uuidString,
            amountMoney: Money(amount: amountInCents, currency: .USD),
            processingMode: .onlineOnly
        )
        
        // Create prompt parameters based on available methods
        let promptParameters = createPromptParameters(availableInputMethods)
        
        // Start the payment
        paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
            paymentParameters,
            promptParameters: promptParameters,
            from: presentedVC,
            delegate: PaymentDelegate(
                service: self,
                completion: completion
            )
        )
    }
    
    // MARK: - Private Methods
    
    /// Authorize the Mobile Payments SDK
    private func authorizeSDK(accessToken: String, locationID: String) {
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
    
    /// Create prompt parameters based on available methods
    private func createPromptParameters(_ availableInputMethods: CardInputMethods) -> PromptParameters {
        // Use a consistent approach that doesn't rely on specific enum values
        // that might change between SDK versions
        
        // For all cases, use the default mode with appropriate additional methods
        return PromptParameters(
            mode: .default,
            additionalMethods: .all
        )
        
        /* Commenting out enum-specific code that's causing errors
        if availableInputMethods.isEmpty {
            // No card readers - use manual card entry with all additional methods
            return PromptParameters(
                mode: .default,
                additionalMethods: .all
            )
        } else if isOnlyMethodAvailable(availableInputMethods, method: "contactless") {
            // Only contactless is available
            return PromptParameters(
                mode: .tap,
                additionalMethods: .all
            )
        } else if isOnlyMethodAvailable(availableInputMethods, method: "chip") {
            // Only chip is available
            return PromptParameters(
                mode: .dip,
                additionalMethods: .all
            )
        } else if isOnlyMethodAvailable(availableInputMethods, method: "magstripe") {
            // Only swipe is available
            return PromptParameters(
                mode: .swipe,
                additionalMethods: .all
            )
        } else {
            // Multiple methods available
            return PromptParameters(
                mode: .default,
                additionalMethods: .all
            )
        }
        */
    }
    
    /// Helper to check if only one method is available
    private func isOnlyMethodAvailable(_ methods: CardInputMethods, method: String) -> Bool {
        // This is a placeholder implementation
        // You'll need to implement this based on how CardInputMethods actually works
        return false
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
            if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
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
    private class PaymentDelegate: NSObject, PaymentManagerDelegate {
        private weak var service: SquarePaymentService?
        private let completion: (Bool, String?) -> Void
        
        init(service: SquarePaymentService, completion: @escaping (Bool, String?) -> Void) {
            self.service = service
            self.completion = completion
            super.init()
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                print("Payment successful with ID: \(String(describing: payment.id))")
                self.completion(true, payment.id)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                self.service?.paymentError = error.localizedDescription
                print("Payment failed: \(error.localizedDescription)")
                self.completion(false, nil)
            }
        }
        
        func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                self.service?.paymentError = "Payment was canceled"
                print("Payment was canceled by user")
                self.completion(false, nil)
            }
        }
    }
}
