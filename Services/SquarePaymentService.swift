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
    
    init(authService: SquareAuthService) {
        self.authService = authService
        super.init()
        locationManager.delegate = self
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
            self.connectionStatus = "SDK already authorized"
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
                        print("error: \(authError.localizedDescription)")
                        return
                    }

                    self.connectionStatus = "SDK authorized"
                    print("Square Mobile Payments SDK successfully authorized.")
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
        case .denied, .restricted:
            paymentError = "Location permission is required for payments"
        case .notDetermined:
            print("Location permission not determined yet")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    // Request Bluetooth permissions
    private func requestBluetoothPermissions() {
        guard CBManager.authorization == .notDetermined else {
            return
        }

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: nil
        )
    }
    
    // Connect to a reader
    func connectToReader() {
        // Ensure SDK is initialized
        if MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized {
            initializeSDK()
            return
        }
        
        // Update connection status
        connectionStatus = "Ready to accept payment"
        isReaderConnected = true
    }
    
    // Process a payment
    func processPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        guard authService.isAuthenticated, let _ = authService.accessToken else {
            paymentError = "Not authenticated with Square"
            completion(false, "Not authenticated with Square")
            return
        }
        
        // Ensure SDK is initialized
        if MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized {
            initializeSDK()
        }
        
        isProcessingPayment = true
        paymentError = nil
        
        // Create a money amount in the smallest denomination (cents)
        let amountInCents = UInt(amount * 100) // Changed from Int to UInt
        
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
            
            // Create payment parameters
            let paymentParameters = PaymentParameters(
                idempotencyKey: UUID().uuidString,
                amountMoney: Money(amount: amountInCents, currency: .USD), // Changed from Int64 to UInt
                processingMode: .onlineOnly
            )
            
            // Start the payment
            paymentHandle = MobilePaymentsSDK.shared.paymentManager.startPayment(
                paymentParameters,
                promptParameters: PromptParameters(
                    mode: .default,
                    additionalMethods: .all
                ),
                from: presentedVC,
                delegate: PaymentDelegate(
                    service: self,
                    completion: completion
                )
            )
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
        
        public func paymentManager(_ paymentManager: PaymentManager, didFinish payment: Payment) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                print("Payment Did Finish: \(payment)")
                self.completion(true, payment.id)
            }
        }
        
        public func paymentManager(_ paymentManager: PaymentManager, didFail payment: Payment, withError error: Error) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                self.service?.paymentError = error.localizedDescription
                print("Payment Failed: \(error.localizedDescription)")
                self.completion(false, nil)
            }
        }
        
        public func paymentManager(_ paymentManager: PaymentManager, didCancel payment: Payment) {
            DispatchQueue.main.async {
                self.service?.isProcessingPayment = false
                print("Payment Canceled")
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
        case .poweredOff:
            paymentError = "Bluetooth is powered off. Please turn it on to use card readers."
        case .resetting:
            print("Bluetooth is resetting.")
        case .unauthorized:
            paymentError = "Bluetooth permission is required for card readers."
        case .unsupported:
            paymentError = "This device does not support Bluetooth."
        case .unknown:
            print("Bluetooth state is unknown.")
        @unknown default:
            print("Unknown Bluetooth state.")
        }
    }
}
