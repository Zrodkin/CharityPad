//
//  SquarePaymentService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//

import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

/// Main service class that orchestrates Square payment functionality
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
    @Published var supportsTapToPay = false
    @Published var supportsOfflinePayments = false
    @Published var hasAvailablePaymentMethods = false
    @Published var offlinePendingCount = 0
    
    // MARK: - Services
    
    private let authService: SquareAuthService
    private let sdkInitializationService: SquareSDKInitializationService
    private let readerConnectionService: SquareReaderConnectionService
    private let paymentProcessingService: SquarePaymentProcessingService
    private let permissionService: SquarePermissionService
    private let offlinePaymentService: SquareOfflinePaymentService
    private let tapToPayService: SquareTapToPayService
    
    // MARK: - Private Properties
    
    private var readerService: SquareReaderService?
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService) {
        self.authService = authService
        
        // Initialize services
        self.sdkInitializationService = SquareSDKInitializationService()
        self.readerConnectionService = SquareReaderConnectionService()
        self.paymentProcessingService = SquarePaymentProcessingService()
        self.permissionService = SquarePermissionService()
        self.offlinePaymentService = SquareOfflinePaymentService()
        self.tapToPayService = SquareTapToPayService()
        
        super.init()
        
        // Configure services with dependencies
        self.sdkInitializationService.configure(with: authService, paymentService: self)
        self.permissionService.configure(with: self)
        self.readerConnectionService.configure(with: self, permissionService: permissionService)
        self.paymentProcessingService.configure(with: self, authService: authService)
        self.offlinePaymentService.configure(with: self)
        self.tapToPayService.configure(with: self, authService: authService)
        
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
    
    /// Check if SDK is initialized and fully ready
    func checkIfInitialized() -> Bool {
        return sdkInitializationService.checkIfInitialized()
    }
    
    /// Set the reader service - called after initialization
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
        self.readerConnectionService.setReaderService(readerService)
    }
    
    /// Debug function to explore Square SDK
    func debugSquareSDK() {
        sdkInitializationService.debugSquareSDK()
    }
    
    /// Initialize the Square SDK
    func initializeSDK() {
        sdkInitializationService.initializeSDK(onSuccess: {
            // After initialization succeeds, check additional states
            self.offlinePaymentService.checkOfflinePayments()
            self.tapToPayService.checkTapToPayCapability()
            self.updateAvailablePaymentMethods()
            self.connectToReader()
        })
    }
    
    /// Check if the Square SDK is currently authorized
    func isSDKAuthorized() -> Bool {
        return sdkInitializationService.isSDKAuthorized()
    }
    
    /// Deauthorize the Square SDK
    func deauthorizeSDK(completion: @escaping () -> Void = {}) {
        sdkInitializationService.deauthorizeSDK(completion: completion)
    }
    
    /// Connect to a Square reader
    func connectToReader() {
        readerConnectionService.connectToReader()
    }
    
    /// Update available payment methods based on current reader status
    func updateAvailablePaymentMethods() {
        // Delegate to services to check available methods
        let cardMethods = sdkInitializationService.availableCardInputMethods()
        let isTapToPayCapable = tapToPayService.isDeviceCapable()
        
        DispatchQueue.main.async {
            // Update individual payment method flags
            self.supportsContactless = cardMethods.contains(.contactless)
            self.supportsChip = cardMethods.contains(.chip)
            self.supportsSwipe = cardMethods.contains(.swipe)
            self.supportsTapToPay = isTapToPayCapable
            
            // Set overall availability flag
            self.hasAvailablePaymentMethods = !cardMethods.isEmpty || isTapToPayCapable
            
            // Log available methods for debugging
            print("Available payment methods updated:")
            print("- Contactless: \(self.supportsContactless)")
            print("- Chip: \(self.supportsChip)")
            print("- Swipe: \(self.supportsSwipe)")
            print("- Tap to Pay: \(self.supportsTapToPay)")
        }
    }
    
    /// Process a payment with optional offline support
    func processPayment(amount: Double, allowOffline: Bool = true, completion: @escaping (Bool, String?) -> Void) {
        paymentProcessingService.processPayment(amount: amount, allowOffline: allowOffline, supportsOfflinePayments: supportsOfflinePayments, completion: completion)
    }
    
    /// Process a payment using Apple Tap to Pay on iPhone
    func processTapToPayPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        tapToPayService.processTapToPayPayment(amount: amount, completion: completion)
    }
    
    /// Check for pending offline payments
    func checkOfflinePayments() {
        offlinePaymentService.checkOfflinePayments()
    }
    
    /// Register as observer for offline payment status changes
    func startMonitoringOfflinePayments() {
        offlinePaymentService.startMonitoringOfflinePayments()
    }
    
    /// Stop monitoring offline payment status changes
    func stopMonitoringOfflinePayments() {
        offlinePaymentService.stopMonitoringOfflinePayments()
    }
    
    // MARK: - Private Methods
    
    @objc private func handleAuthenticationSuccess(_ notification: Notification) {
        // Initialize SDK after successful authentication
        DispatchQueue.main.async {
            self.initializeSDK()
        }
    }
}
