import SwiftUI
import SquareMobilePaymentsSDK

struct UpdatedCheckoutView: View {
    let amount: Double
    let isCustomAmount: Bool
    
    // Environment objects
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @EnvironmentObject private var catalogService: SquareCatalogService
    @EnvironmentObject private var paymentService: UpdatedSquarePaymentService
    
    // Navigation via callback function
    var onDismiss: () -> Void
    
    // State
    @State private var showingThankYou = false
    @State private var showingError = false
    @State private var showingSquareAuth = false
    @State private var processingState: ProcessingState = .ready
    @State private var orderId: String? = nil
    
    // Processing state enum
    enum ProcessingState {
        case ready
        case creatingOrder
        case processingPayment
        case completed
        case error
    }
    
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
                
                // Status section
                statusSection
                
                // Process payment button
                Button(action: processPayment) {
                    HStack {
                        Image(systemName: buttonIcon)
                        Text(buttonText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(buttonColor)
                    )
                    .foregroundColor(.white)
                    .font(.headline)
                }
                .disabled(isButtonDisabled)
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
            if !paymentService.isReaderConnected {
                paymentService.connectToReader()
            }
        }
        .onReceive(paymentService.$paymentError) { error in
            // Check if there's an error
            if error != nil {
                processingState = .error
                showingError = true
            }
        }
        .onReceive(paymentService.$isProcessingPayment) { isProcessing in
            // Update state based on payment processing
            if isProcessing {
                processingState = .processingPayment
            } else if processingState == .processingPayment && !isProcessing {
                // Payment processing finished
                if paymentService.paymentError == nil {
                    // Success
                    processingState = .completed
                    showingThankYou = true
                }
            }
        }
        .sheet(isPresented: $showingSquareAuth) {
            SquareAuthorizationView()
        }
    }
    
    // MARK: - Helper Views
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            // Connection status
            HStack {
                Circle()
                    .fill(paymentService.isReaderConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(paymentService.isReaderConnected ?
                    "Ready to process payment" :
                    "Card reader not connected. Please contact staff.")
                    .foregroundColor(.white)
            }
            
            // Processing status (if applicable)
            if processingState == .creatingOrder {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Creating order...")
                        .foregroundColor(.white)
                }
            } else if processingState == .processingPayment {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Processing payment...")
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical)
    }
    
    private var buttonIcon: String {
        switch processingState {
        case .ready:
            return "creditcard"
        case .creatingOrder, .processingPayment:
            return "hourglass"
        case .completed:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.circle"
        }
    }
    
    private var buttonText: String {
        switch processingState {
        case .ready:
            return "Process Payment"
        case .creatingOrder:
            return "Creating Order..."
        case .processingPayment:
            return "Processing..."
        case .completed:
            return "Completed"
        case .error:
            return "Try Again"
        }
    }
    
    private var buttonColor: Color {
        switch processingState {
        case .ready:
            return Color.blue
        case .creatingOrder, .processingPayment:
            return Color.gray
        case .completed:
            return Color.green
        case .error:
            return Color.red
        }
    }
    
    private var isButtonDisabled: Bool {
        return processingState == .creatingOrder ||
               processingState == .processingPayment ||
               processingState == .completed ||
               !paymentService.isReaderConnected
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
                
                // Optional: Display order ID
                if let orderId = orderId {
                    Text("Order ID: \(orderId)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
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
                
                Text(paymentService.paymentError ?? "Payment processing failed")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Button("Try Again") {
                    resetPaymentState()
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
        // Check if authenticated first
        if !squareAuthService.isAuthenticated {
            showingSquareAuth = true
            return
        }
        
        // Check if reader connected
        if !paymentService.isReaderConnected {
            paymentService.paymentError = "Card reader not connected. Please contact staff."
            showingError = true
            return
        }
        
        // Reset state
        resetPaymentState()
        
        // Find catalog item ID if using preset amount
        var catalogItemId: String? = nil
        
        if !isCustomAmount {
            // Try to find matching preset donation with catalog ID
            if let donation = kioskStore.presetDonations.first(where: { Double($0.amount) == amount }) {
                catalogItemId = donation.catalogItemId
            }
        }
        
        // Set state to creating order
        processingState = .creatingOrder
        
        // Process the payment with catalog integration
        paymentService.processPayment(
            amount: amount,
            isCustomAmount: isCustomAmount,
            catalogItemId: catalogItemId
        ) { success, transactionId in
            // Update UI based on result
            if success {
                // Record donation
                donationViewModel.recordDonation(amount: amount, transactionId: transactionId)
                
                // Store order ID for display
                orderId = paymentService.currentOrderId
                
                // Show success
                processingState = .completed
                showingThankYou = true
            } else {
                // The error will be displayed via the paymentError binding
                processingState = .error
                showingError = true
            }
        }
    }
    
    private func resetPaymentState() {
        processingState = .ready
        showingError = false
        showingThankYou = false
        orderId = nil
    }
}

struct UpdatedCheckoutView_Previews: PreviewProvider {
    static var previews: some View {
        UpdatedCheckoutView(amount: 50.0, isCustomAmount: false, onDismiss: {})
            .environmentObject(KioskStore())
            .environmentObject(DonationViewModel())
            .environmentObject(SquareAuthService())
            .environmentObject(SquareCatalogService(authService: SquareAuthService()))
            .environmentObject(UpdatedSquarePaymentService(
                authService: SquareAuthService(),
                catalogService: SquareCatalogService(authService: SquareAuthService())
            ))
    }
}
