//
//  SquareSDKInitializationService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//

import Foundation
import SquareMobilePaymentsSDK

/// Service responsible for Square SDK initialization and authorization
class SquareSDKInitializationService: NSObject, AuthorizationStateObserver {
    // MARK: - Private Properties
    
    private weak var authService: SquareAuthService?
    private weak var paymentService: SquarePaymentService?
    private var isInitialized = false
    private var tapToPaySettings: TapToPaySettings?
    
    // MARK: - Public Methods
    
    /// Configure the service with necessary dependencies
    func configure(with authService: SquareAuthService, paymentService: SquarePaymentService) {
        self.authService = authService
        self.paymentService = paymentService
    }
    
    /// Check if the Square SDK is initialized and ready to use
    func checkIfInitialized() -> Bool {
        // First make sure the shared instance is available
        guard let _ = try? MobilePaymentsSDK.shared else {
            print("Square SDK not initialized yet - shared instance not available")
            return false
        }
        
        // Mark as initialized if we get here
        if !isInitialized {
            isInitialized = true
            
            // Register as authorization observer
            MobilePaymentsSDK.shared.authorizationManager.add(self)
            
            // Store reference to Tap to Pay settings
            tapToPaySettings = MobilePaymentsSDK.shared.tapToPaySettings
            
            print("Square SDK initialized and available")
        }
        
        return true
    }
    
    /// Debug function to print SDK information
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
        
        // Check for Tap to Pay capability
        if let tapToPaySettings = tapToPaySettings {
            print("Device supports Tap to Pay: \(tapToPaySettings.isDeviceCapable)")
            
            // Check if Apple account is linked
            tapToPaySettings.isAppleAccountLinked { isLinked, error in
                print("Apple account linked for Tap to Pay: \(isLinked)")
                if let error = error {
                    print("Error checking Apple account linking: \(error.localizedDescription)")
                }
            }
        } else {
            print("Tap to Pay settings not available")
        }
        
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
    
    /// Initialize the Square Mobile Payments SDK
    func initializeSDK(onSuccess: @escaping () -> Void = {}) {
        // Check if SDK is available first
        guard checkIfInitialized() else {
            updateConnectionStatus("SDK not initialized")
            return
        }
        
        // Get credentials from auth service
        guard let authService = authService,
              let accessToken = authService.accessToken,
              let locationID = authService.locationId else {
            
            // Fallback to merchantId if locationId is not available (not recommended)
            if let authService = authService,
               let accessToken = authService.accessToken,
               let fallbackID = authService.merchantId {
                updatePaymentError("No location ID available, using merchant ID as fallback")
                updateConnectionStatus("Using fallback ID")
                print("WARNING: Using merchant ID as fallback for location ID. This might not work correctly.")
                
                // Continue with merchantId as fallback
                authorizeSDK(accessToken: accessToken, locationID: fallbackID, onSuccess: onSuccess)
                return
            }
            
            updatePaymentError("No access token or location ID available")
            updateConnectionStatus("Missing credentials")
            return
        }
        
        // Check if already authorized
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            print("Square SDK already authorized")
            updateConnectionStatus("SDK already authorized")
            onSuccess()
            return
        }
        
        // Authorize the SDK with locationID
        print("Authorizing Square SDK with access token and location ID: \(locationID)")
        MobilePaymentsSDK.shared.authorizationManager.authorize(
            withAccessToken: accessToken,
            locationID: locationID
        ) { [weak self] error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let authError = error {
                    self.updatePaymentError("Authorization error: \(authError.localizedDescription)")
                    self.updateConnectionStatus("Authorization failed")
                    print("Square SDK authorization error: \(authError.localizedDescription)")
                    return
                }
                
                self.updateConnectionStatus("SDK authorized")
                print("Square Mobile Payments SDK successfully authorized.")
                onSuccess()
            }
        }
    }
    
    /// Check if the Square SDK is authorized
    func isSDKAuthorized() -> Bool {
        guard checkIfInitialized() else { return false }
        return MobilePaymentsSDK.shared.authorizationManager.state == .authorized
    }
    
    /// Deauthorize the Square SDK
    func deauthorizeSDK(completion: @escaping () -> Void = {}) {
        guard checkIfInitialized() else {
            completion()
            return
        }
        
        MobilePaymentsSDK.shared.authorizationManager.deauthorize {
            DispatchQueue.main.async { [weak self] in
                self?.updateConnectionStatus("Disconnected")
                
                // Update reader connected state
                if let paymentService = self?.paymentService {
                    paymentService.isReaderConnected = false
                }
                
                completion()
            }
        }
    }
    
    /// Get the currently available card input methods
    func availableCardInputMethods() -> CardInputMethods {
        guard checkIfInitialized() else { return CardInputMethods() }
        return MobilePaymentsSDK.shared.paymentManager.availableCardInputMethods
    }
    
    // MARK: - AuthorizationStateObserver
    
    func authorizationStateDidChange(_ authorizationState: AuthorizationState) {
        DispatchQueue.main.async { [weak self] in
            if authorizationState == .authorized {
                self?.updateConnectionStatus("SDK authorized")
                self?.paymentService?.connectToReader()
            } else {
                self?.updateConnectionStatus("Not authorized")
                
                // Update reader connected state
                if let paymentService = self?.paymentService {
                    paymentService.isReaderConnected = false
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Authorize the Mobile Payments SDK
    private func authorizeSDK(accessToken: String, locationID: String, onSuccess: @escaping () -> Void = {}) {
        // Make sure initialized first
        guard checkIfInitialized() else { return }
        
        // Check if already authorized
        guard MobilePaymentsSDK.shared.authorizationManager.state == .notAuthorized else {
            DispatchQueue.main.async {
                self.updateConnectionStatus("SDK already authorized")
                onSuccess()
            }
            return
        }
        
        // Authorize with Square
        MobilePaymentsSDK.shared.authorizationManager.authorize(
            withAccessToken: accessToken,
            locationID: locationID
        ) { [weak self] error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let authError = error {
                    self.updatePaymentError("Authorization error: \(authError.localizedDescription)")
                    self.updateConnectionStatus("Authorization failed")
                    print("Square SDK authorization error: \(authError.localizedDescription)")
                    return
                }
                
                self.updateConnectionStatus("SDK authorized")
                print("Square Mobile Payments SDK successfully authorized.")
                onSuccess()
            }
        }
    }
    
    /// Update the connection status in the payment service
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.connectionStatus = status
        }
    }
    
    /// Update payment error in the payment service
    private func updatePaymentError(_ error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.paymentError = error
        }
    }
}
