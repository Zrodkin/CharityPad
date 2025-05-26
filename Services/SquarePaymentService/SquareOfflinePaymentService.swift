import Foundation
import SquareMobilePaymentsSDK

/// Service responsible for handling offline payments
class SquareOfflinePaymentService: NSObject {
    // MARK: - Private Properties
    
    private weak var paymentService: SquarePaymentService?
    private var offlinePayments: [String: OfflinePayment] = [:]
    
    // MARK: - Public Methods
    
    /// Configure the service with necessary dependencies
    func configure(with paymentService: SquarePaymentService) {
        self.paymentService = paymentService
    }
    
    /// Check for pending offline payments
    func checkOfflinePayments() {
        // Check if SDK is initialized and authorized
        if !isSDKAuthorized() {
            updateSupportsOfflinePayments(false)
            updateOfflinePendingCount(0)
            return
        }
        
        // Get the offline payment queue
        let paymentManager = MobilePaymentsSDK.shared.paymentManager
        let offlineQueue = paymentManager.offlinePaymentQueue
        
        // Get offline payments - Fixed to match official documentation
        offlineQueue.getPayments { [weak self] payments, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error getting offline payments: \(error.localizedDescription)")
                self.updateSupportsOfflinePayments(false)
                self.updateOfflinePendingCount(0)
                return
            }
            
            // Count queued payments
            let queuedPayments = payments.filter { $0.status == .queued }
            let pendingCount = queuedPayments.count
            
            // Store references to offline payments
            for payment in payments {
                self.offlinePayments[payment.localID] = payment
            }
            
            self.updateSupportsOfflinePayments(true)
            self.updateOfflinePendingCount(pendingCount)
            
            if pendingCount > 0 {
                self.updateConnectionStatus("You have \(pendingCount) offline payment\(pendingCount == 1 ? "" : "s") pending")
            }
        }
    }
    
    /// Start monitoring offline payment status
    func startMonitoringOfflinePayments() {
        // Since we don't know how to observe changes based on the documentation,
        // we'll implement a simple polling mechanism
        checkOfflinePayments()
    }
    
    /// Stop monitoring offline payment status
    func stopMonitoringOfflinePayments() {
        // No action needed for polling
    }
    
    // MARK: - Private Methods
    
    /// Check if the SDK is initialized and authorized
    private func isSDKAuthorized() -> Bool {
        // Check authorization state directly
        return MobilePaymentsSDK.shared.authorizationManager.state == .authorized
    }
    
    /// Helper method to handle offline payment status changes
    private func handleOfflinePaymentStatusChange(_ payment: OfflinePayment, newStatus: OfflineStatus) {
        DispatchQueue.main.async { [weak self] in
            switch newStatus {
            case .queued:
                // Payment is still queued, nothing to do
                break
                
            case .uploaded:
                if let uploadTime = payment.uploadedAt {
                    // Payment successfully uploaded
                    print("Offline payment \(payment.localID) was uploaded at \(uploadTime)")
                    
                    // Notify the user if needed
                    if let offlinePendingCount = self?.paymentService?.offlinePendingCount, offlinePendingCount <= 1 {
                        self?.updateConnectionStatus("All offline payments processed")
                    }
                }
                
            case .processed:
                // Payment has been successfully processed by Square Server
                print("Offline payment \(payment.localID) has been processed successfully")
                self?.updateConnectionStatus("Offline payment processed successfully")
                
            case .failedToProcess:
                // Payment failed to process
                print("Offline payment \(payment.localID) failed to process")
                self?.updatePaymentError("An offline payment failed to process. Please check your Square dashboard.")
                
            case .failedToUpload:
                // Payment failed to upload
                print("Offline payment \(payment.localID) failed to upload")
                self?.updatePaymentError("An offline payment failed to upload. Please check your connection.")
                
            case .unknown:
                // Status is unknown
                print("Offline payment \(payment.localID) has unknown status")
                self?.updatePaymentError("An offline payment has unknown status. Please check your Square dashboard.")
                
            @unknown default:
                // Handle future cases
                print("Offline payment \(payment.localID) has unhandled status: \(newStatus)")
                break
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
    
    /// Update the supportsOfflinePayments flag in payment service
    private func updateSupportsOfflinePayments(_ supported: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.supportsOfflinePayments = supported
        }
    }
    
    /// Update the offlinePendingCount in payment service
    private func updateOfflinePendingCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.paymentService?.offlinePendingCount = count
        }
    }
}
