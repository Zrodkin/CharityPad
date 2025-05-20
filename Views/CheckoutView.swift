import SwiftUI
import SquareMobilePaymentsSDK

struct CheckoutView: View {
    let amount: Double
    
    // Environment objects
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @EnvironmentObject private var squarePaymentService: SquarePaymentService
    
    // Navigation via callback function
    var onDismiss: () -> Void
    
    // State
    @State private var showingThankYou = false
    @State private var showingError = false
    @State private var showingSquareAuth = false
    
    var body: some View {
        ZStack {
            // Background
            if let backgroundImage = kioskStore.backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .blur(radius: 5)
            } else {
                // Use a simple color instead of gradient to avoid compatibility issues
                Color.blue
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Content overlay
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 30) {
                // Title & Amount
                Text("Donation Amount")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(formatAmount(amount))
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                // Connection status indicator - simplified for kiosk mode
                connectionStatusView
                
                // Process payment button
                Button(action: processPayment) {
                    HStack {
                        Image(systemName: squarePaymentService.isProcessingPayment ? "hourglass" : "creditcard")
                        Text(squarePaymentService.isProcessingPayment ? "Processing..." : "Process Payment")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
                    .foregroundColor(.white)
                    .font(.headline)
                }
                .disabled(squarePaymentService.isProcessingPayment || !squarePaymentService.isReaderConnected)
                .padding(.horizontal)
                
                // Cancel button
                Button("Cancel") {
                    onDismiss()
                }
                .foregroundColor(.white)
                .padding()
            }
            .padding()
            
            // Success overlay
            if showingThankYou {
                thankYouOverlay
            }
            
            // Error overlay
            if showingError {
                errorOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: Button(action: {
            onDismiss()
        }) {
            Image(systemName: "chevron.left")
                .foregroundColor(.white)
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.2)))
        })
        .onAppear {
            // In kiosk mode, we just check if reader is connected but don't offer pairing
            if !squarePaymentService.isReaderConnected {
                squarePaymentService.connectToReader()
            }
        }
        .onReceive(squarePaymentService.$paymentError) { _ in
            // Check if there's an error by accessing the published property directly
            if squarePaymentService.paymentError != nil {
                self.showingError = true
            }
        }
        .sheet(isPresented: $showingSquareAuth) {
            SquareAuthorizationView()
        }
    }
    
    // MARK: - Helper Views
    
    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(squarePaymentService.isReaderConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            Text(squarePaymentService.isReaderConnected ?
                "Ready to process payment" :
                "Card reader not connected. Please contact staff.")
                .foregroundColor(.white)
        }
        .padding(.vertical)
    }
    
    private var thankYouOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.green)
                
                Text("Thank You!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Your donation has been processed.")
                    .foregroundColor(.white)
                
                Button("Done") {
                    onDismiss()
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.top, 20)
            }
            .padding()
        }
        .onAppear {
            // Auto dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                onDismiss()
            }
        }
    }
    
    private var errorOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.red)
                
                Text("Payment Failed")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(squarePaymentService.paymentError ?? "Payment processing failed")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Button("Try Again") {
                    showingError = false
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.top, 20)
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
    
    private func processPayment() {
        // Check if authenticated
        if !squareAuthService.isAuthenticated {
            showingSquareAuth = true
            return
        }
        
        // Check if reader connected
        if !squarePaymentService.isReaderConnected {
            // In kiosk mode, just show an error - no pairing functionality
            squarePaymentService.paymentError = "Card reader not connected. Please contact staff."
            showingError = true
            return
        }
        
        // Use the actual Square payment processing
        squarePaymentService.processPayment(amount: amount) { success, transactionId in
            if success, let transactionId = transactionId {
                // Record donation
                donationViewModel.recordDonation(amount: amount, transactionId: transactionId)
                
                // Show success
                showingThankYou = true
            } else {
                // The error will be displayed via the paymentError binding
                showingError = true
            }
        }
    }
}
