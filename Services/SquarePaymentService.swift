import Foundation
import SwiftUI
import SquareMobilePaymentsSDK
import CoreLocation
import CoreBluetooth

class SquarePaymentService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isProcessingPayment = false
    @Published var paymentError: String? = nil
    @Published var isReaderConnected = false
    @Published var connectionStatus: String = "Disconnected"
    
    private let authService: SquareAuthService
    private var paymentHandle: PaymentHandle?
    private lazy var locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var readerService: SquareReaderService?
    
    init(authService: SquareAuthService) {
        self.authService = authService
        super.init()
        locationManager.delegate = self
    }
    
    // Set the reader service - this will be called after initialization
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
    }
    
    // Initialize the Square SDK
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
        authorizeMobilePaymentsSDK(accessToken: accessToken, locationID: locationID)
    }
    
    // Authorize the Mobile Payments SDK
    private func authorizeMobilePaymentsSDK(accessToken: String, locationID: String) {
        guard MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized else {
            DispatchQueue.main.async {
                self.connectionStatus = "SDK already authorized"
                self.updateConnectionStatus()
            }
            return
        }

        MobilePaymentsSDK.shared.authorizationManager.authorize(
           withAccessToken: accessToken,
            locationID: locationID) { error in
                DispatchQueue.main.async {
                    if let authError = error {
                        // Handle auth error
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
    
    // Request location permission
    private func requestLocationPermission() {
        let authorizationStatus = locationManager.authorizationStatus
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            paymentError = "Location permission is required for payments"
            print("Show UI directing the user to the iOS Settings app")
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location services have already been authorized.")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    // CLLocationManagerDelegate method
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location permission granted")
            // Attempt to initialize SDK again if we have the necessary credentials
            if let accessToken = authService.accessToken,
               let locationID = authService.merchantId {
                authorizeMobilePaymentsSDK(accessToken: accessToken, locationID: locationID)
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
    
    // Request Bluetooth permissions
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
    
    // Connect to a reader - updated to check the reader service first
    func connectToReader() {
        // Ensure SDK is initialized
        if MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized {
            if let accessToken = authService.accessToken,
               let locationID = authService.merchantId {
                authorizeMobilePaymentsSDK(accessToken: accessToken, locationID: locationID)
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
        if locationManager.authorizationStatus != .authorizedWhenInUse &&
           locationManager.authorizationStatus != .authorizedAlways {
            DispatchQueue.main.async {
                self.paymentError = "Location permission is required for connecting to readers"
                self.connectionStatus = "Location access needed"
            }
            return
        }
        
        // Check if we have any readers via the reader service
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
            
            // Check if we have a ready reader
            if let readyReader = readerService.readers.first(where: { $0.state == .ready }) {
                readerService.selectReader(readyReader)
                DispatchQueue.main.async {
                    self.connectionStatus = "Connected to \(readyReader.model == .stand ? "Square Stand" : "Square Reader")"
                    self.isReaderConnected = true
                    self.paymentError = nil
                }
                return
            }
            
            // Check if we have a selected reader that's not ready
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
        
        // Fallback behavior if reader service is not available
        // Check if SDK is authorized, assume we're ready to take payments
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            DispatchQueue.main.async {
                self.connectionStatus = "Ready to accept payment"
                self.isReaderConnected = true
            }
        }
    }
    
    // Update connection status based on reader state
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
    
    // Process a payment
    func processPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        guard authService.isAuthenticated, let _ = authService.accessToken else {
            paymentError = "Not authenticated with Square"
            completion(false, nil)
            return
        }
        
        // Ensure SDK is initialized
        if MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized {
            initializeSDK()
            completion(false, nil)
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessingPayment = true
            self.paymentError = nil
        }
        
        // Create a money amount in the smallest denomination (cents)
        let amountInCents = UInt(amount * 100) // Using UInt to ensure positive values only
        
        // Find the top view controller to present the payment UI
        if let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first,
           let topController = windowScene.windows.first?.rootViewController {
            
            var presentedVC = topController
            while let presented = presentedVC.presentedViewController {
                presentedVC = presented
            }
            
            // Determine which input methods are available
            let availableInputMethods = readerService?.availableCardInputMethods ?? MobilePaymentsSDK.shared.paymentManager.availableCardInputMethods
            
            // Create payment parameters with appropriate Idempotency key
            let paymentParameters = PaymentParameters(
                idempotencyKey: UUID().uuidString,
                amountMoney: Money(amount: amountInCents, currency: .USD),
                processingMode: .onlineOnly
            )
            
            // Determine which prompt parameters to use based on available methods
            let promptParameters: PromptParameters
            
            if availableInputMethods.isEmpty {
                // No card readers - use manual card entry with all additional methods
                promptParameters = PromptParameters(
                    mode: .default,
                    additionalMethods: .all
                )
            } else if availableInputMethods == [.tap] {
                // Only contactless is available
                promptParameters = PromptParameters(
                    mode: .tap,
                    additionalMethods: .all
                )
            } else if availableInputMethods == [.dip] {
                // Only chip is available
                promptParameters = PromptParameters(
                    mode: .dip,
                    additionalMethods: .all
                )
            } else if availableInputMethods == [.swipe] {
                // Only swipe is available
                promptParameters = PromptParameters(
                    mode: .swipe,
                    additionalMethods: .all
                )
            } else {
                // Multiple methods available
                promptParameters = PromptParameters(
                    mode: .default,
                    additionalMethods: .all
                )
            }
            
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
        } else {
            DispatchQueue.main.async {
                self.isProcessingPayment = false
                self.paymentError = "Unable to find view controller to present payment UI"
                completion(false, nil)
            }
        }
    }
    
    // Helper class to handle payment callbacks
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
                print("Payment successful with ID: \(payment.id)")
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

// MARK: - CBCentralManagerDelegate
extension SquarePaymentService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on and ready for use.")
            // If SDK is authorized, try to connect to reader
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
            print("Bluetooth is resetting.")
        case .unauthorized:
            DispatchQueue.main.async {
                self.paymentError = "Bluetooth permission is required for card readers."
                self.isReaderConnected = false
                self.connectionStatus = "Bluetooth permission denied"
            }
        case .unsupported:
            DispatchQueue.main.async {
                self.paymentError = "This device does not support Bluetooth."
                self.isReaderConnected = false
                self.connectionStatus = "Bluetooth not supported"
            }
        case .unknown:
            print("Bluetooth state is unknown.")
        @unknown default:
            print("Unknown Bluetooth state.")
        }
    }
}
