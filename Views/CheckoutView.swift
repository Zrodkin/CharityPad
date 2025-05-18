import SwiftUI
import SquareMobilePaymentsSDK

struct CheckoutView: View {
    let amount: Double
    
    // Environment objects
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var donationViewModel: DonationViewModel
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @EnvironmentObject private var squarePaymentService: SquarePaymentService
    @EnvironmentObject private var squareReaderService: SquareReaderService
    
    // Navigation - using @State with dismiss method pattern instead of Environment
    @State private var shouldDismiss = false
    
    // State
    @State private var isProcessing = false
    @State private var showingThankYou = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingReaderSelection = false
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
                
                // Connection status
                connectionStatusView
                
                // Process payment button
                Button(action: processPayment) {
                    HStack {
                        Image(systemName: isProcessing ? "hourglass" : "creditcard")
                        Text(isProcessing ? "Processing..." : "Process Payment")
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
                .disabled(isProcessing)
                .padding(.horizontal)
                
                // Cancel button
                Button("Cancel") {
                    shouldDismiss = true
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
            shouldDismiss = true
        }) {
            Image(systemName: "chevron.left")
                .foregroundColor(.white)
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.2)))
        })
        .onAppear {
            // Check if the reader is connected
            if !squarePaymentService.isReaderConnected {
                squarePaymentService.connectToReader()
            }
        }
        .sheet(isPresented: $showingSquareAuth) {
            SquareAuthorizationView()
        }
        .sheet(isPresented: $showingReaderSelection) {
            ReaderSelectionSheet(onDismiss: {
                showingReaderSelection = false
            })
        }
        .navigate(using: $shouldDismiss, destination: EmptyView())
    }
    
    // MARK: - Helper Views
    
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(squarePaymentService.isReaderConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(squarePaymentService.connectionStatus)
                    .foregroundColor(.white)
            }
            
            if !squarePaymentService.isReaderConnected {
                Button("Connect Reader") {
                    if !squareReaderService.readers.isEmpty {
                        showingReaderSelection = true
                    } else {
                        squarePaymentService.connectToReader()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white, lineWidth: 1)
                )
                .foregroundColor(.white)
            }
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
                    shouldDismiss = true
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
                shouldDismiss = true
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
                
                Text(errorMessage)
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
            squarePaymentService.connectToReader()
            return
        }
        
        // Start processing
        isProcessing = true
        
        // Simulate payment processing for demo
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isProcessing = false
            
            // Record donation
            donationViewModel.recordDonation(amount: amount, transactionId: UUID().uuidString)
            
            // Show success
            showingThankYou = true
        }
        
        // In a real app, use the Square SDK to process payment
        /*
        squarePaymentService.processPayment(amount: amount) { success, transactionId in
            isProcessing = false
            
            if success, let transactionId = transactionId {
                // Record donation
                donationViewModel.recordDonation(amount: amount, transactionId: transactionId)
                
                // Show success
                showingThankYou = true
            } else {
                // Show error
                errorMessage = squarePaymentService.paymentError ?? "Payment failed"
                showingError = true
            }
        }
        */
    }
}

// Simple Reader Selection Sheet
struct ReaderSelectionSheet: View {
    @EnvironmentObject private var squareReaderService: SquareReaderService
    @EnvironmentObject private var squarePaymentService: SquarePaymentService
    
    // Using closure for dismissal instead of Environment
    var onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                if squareReaderService.readers.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "creditcard.wireless.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Readers Found")
                            .font(.title2)
                        
                        Text("Would you like to pair a new reader?")
                            .foregroundColor(.gray)
                        
                        Button("Pair New Reader") {
                            squareReaderService.startPairing()
                            onDismiss()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(squareReaderService.readers, id: \.serialNumber) { reader in
                            Button(action: {
                                squareReaderService.selectReader(reader)
                                squarePaymentService.connectToReader()
                                onDismiss()
                            }) {
                                HStack {
                                    Image(systemName: "creditcard.wireless")
                                        .foregroundColor(reader.state == .ready ? .green : .gray)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(squareReaderService.readerModelDescription(reader.model))
                                            .font(.headline)
                                        
                                        Text("S/N: \(String(describing: reader.serialNumber))")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(squareReaderService.readerStateDescription(reader.state))
                                        .foregroundColor(reader.state == .ready ? .green : .orange)
                                        .font(.caption)
                                }
                            }
                            .disabled(reader.state != .ready)
                        }
                        
                        Button("Pair New Reader") {
                            squareReaderService.startPairing()
                            onDismiss()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Select Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// Extension for navigation without using Environment
extension View {
    func navigate<Destination: View>(using binding: Binding<Bool>, destination: Destination) -> some View {
        // Only support iOS 18+
        overlay(
            ZStack {
                // Empty implementation since we're only targeting iOS 18+
                // In a real implementation, you would use the most current navigation API
                if binding.wrappedValue {
                    destination
                        .hidden()
                }
            }
        )
    }
}
