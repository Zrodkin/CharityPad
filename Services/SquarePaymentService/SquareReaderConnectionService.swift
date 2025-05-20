//
//  SquareReaderConnectionService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//
import Foundation
import SquareMobilePaymentsSDK

/// Service responsible for managing connections to Square card readers
class SquareReaderConnectionService: NSObject {
    // MARK: - Private Properties
    
    private weak var paymentService: SquarePaymentService?
    private weak var permissionService: SquarePermissionService?
    private var readerService: SquareReaderService?
    
    // MARK: - Public Methods
    
    /// Configure the service with necessary dependencies
    func configure(with paymentService: SquarePaymentService, permissionService: SquarePermissionService) {
        self.paymentService = paymentService
        self.permissionService = permissionService
    }
    
    /// Set the reader service
    func setReaderService(_ readerService: SquareReaderService) {
        self.readerService = readerService
    }
    
    /// Connect to a Square reader
    func connectToReader() {
        // Ensure SDK is initialized and available
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            // If not authorized, update connection status
            updateConnectionStatus("Square SDK not authorized")
            return
        }
        
        // Check if permission service is available
        guard let permissionService = self.permissionService else {
            updateConnectionStatus("Permission service not configured")
            return
        }
        
        // Check if Bluetooth is enabled
        if !permissionService.isBluetoothAvailable() {
            updatePaymentError("Bluetooth is required for connecting to readers")
            updateConnectionStatus("Bluetooth required")
            return
        }
        
        // Check if location permission is granted
        if !permissionService.isLocationPermissionGranted() {
            updatePaymentError("Location permission is required for connecting to readers")
            updateConnectionStatus("Location access needed")
            return
        }
        
        // Use reader service to find available readers
        if let readerService = readerService {
            if readerService.readers.isEmpty {
                // No readers - start pairing if not in progress
                if !MobilePaymentsSDK.shared.readerManager.isPairingInProgress {
                    updateConnectionStatus("No readers found. Starting pairing...")
                    readerService.startPairing()
                } else {
                    updateConnectionStatus("Searching for readers...")
                }
                return
            }
            
            // If we have a ready reader, select it
            if let readyReader = readerService.readers.first(where: { $0.state == .ready }) {
                readerService.selectReader(readyReader)
                updateConnectionStatus("Connected to \(readyReader.model == .stand ? "Square Stand" : "Square Reader")")
                updateReaderConnected(true)
                updatePaymentError(nil)
                return
            }
            
            // If we have a selected reader that's not ready, show status
            if let selectedReader = readerService.selectedReader, selectedReader.state != .ready {
                updateConnectionStatus("Reader \(readerService.readerStateDescription(selectedReader.state))")
                updateReaderConnected(false)
                return
            }
            
            // If we have readers but none are ready
            updateConnectionStatus("Reader not ready. Please check reader status.")
            updateReaderConnected(false)
            return
        }
        
        // Fallback if reader service isn't available but SDK is authorized
        if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
            updateConnectionStatus("Ready to accept payment")
            updateReaderConnected(true)
        }
    }
    
    /// Update reader connection status
    func updateConnectionStatus() {
        // Make sure reader service is available
        guard let readerService = readerService else {
            if MobilePaymentsSDK.shared.authorizationManager.state == .authorized {
                updateConnectionStatus("Ready for payment")
                updateReaderConnected(true)
            } else {
                updateConnectionStatus("Not connected to Square")
                updateReaderConnected(false)
            }
            return
        }
        
        if readerService.readers.isEmpty {
            updateConnectionStatus("No readers connected")
            updateReaderConnected(false)
            return
        }
        
        if let readyReader = readerService.readers.first(where: { $0.state == .ready }) {
            updateConnectionStatus("Connected to \(readyReader.model == .stand ? "Square Stand" : "Square Reader")")
            updateReaderConnected(true)
            return
        }
        
        // We have readers but none are ready
        if let firstReader = readerService.readers.first {
            updateConnectionStatus("Reader \(readerService.readerStateDescription(firstReader.state))")
            updateReaderConnected(false)
        }
    }
    
    // MARK: - Private Methods
    
    /// Update the connection status in the payment service
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.connectionStatus = status
        }
    }
    
    /// Update reader connected state in the payment service
    private func updateReaderConnected(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.isReaderConnected = connected
        }
    }
    
    /// Update payment error in the payment service
    private func updatePaymentError(_ error: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.paymentError = error
        }
    }
}
