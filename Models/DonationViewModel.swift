import Foundation
import Combine
import SwiftUI

class DonationViewModel: ObservableObject {
    // Donation selection properties
    @Published var selectedAmount: Double?
    @Published var customAmount: String = "0"
    @Published var isCustomAmount: Bool = false
    
    // Transaction status
    @Published var isProcessingPayment: Bool = false
    @Published var paymentSuccess: Bool = false
    @Published var paymentError: String? = nil
    
    // History
    @Published var donations: [Donation] = []
    
    // Preset donation amounts
    @Published var presetAmounts = [18.0, 36.0, 52.0, 78.0, 126.0, 500.0]
    
    init() {
        // Initialize with default values
        loadDonations()
    }
    
    // Format amount as currency
    func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
    
    // Reset donation state
    func resetDonation() {
        selectedAmount = nil
        customAmount = "0"
        isCustomAmount = false
        isProcessingPayment = false
        paymentSuccess = false
        paymentError = nil
    }
    
    // Record a donation
    func recordDonation(amount: Double, transactionId: String? = nil) {
        let donation = Donation(amount: amount, transactionId: transactionId)
        donations.append(donation)
        
        // Save to UserDefaults
        saveDonations()
        
        print("Donation recorded: \(donation.id) - \(formatAmount(donation.amount))")
    }
    
    // Handle payment completion
    func handlePaymentCompletion(success: Bool, transactionId: String? = nil, errorMessage: String? = nil) {
        isProcessingPayment = false
        
        if success {
            paymentSuccess = true
            if let transactionId = transactionId {
                recordDonation(amount: selectedAmount ?? Double(customAmount) ?? 0, transactionId: transactionId)
            } else {
                recordDonation(amount: selectedAmount ?? Double(customAmount) ?? 0)
            }
        } else {
            paymentError = errorMessage ?? "Payment failed"
        }
    }
    
    // Save donations to UserDefaults
    private func saveDonations() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(donations)
            UserDefaults.standard.set(data, forKey: "donations")
        } catch {
            print("Failed to save donations: \(error)")
        }
    }
    
    // Load donations from UserDefaults
    private func loadDonations() {
        if let data = UserDefaults.standard.data(forKey: "donations") {
            do {
                let decoder = JSONDecoder()
                donations = try decoder.decode([Donation].self, from: data)
            } catch {
                print("Failed to load donations: \(error)")
            }
        }
    }
}
