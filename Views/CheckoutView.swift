import SwiftUI
import SquareMobilePaymentsSDK

struct CheckoutView: View {
    let amount: Double
    @EnvironmentObject var kioskStore: KioskStore
    @EnvironmentObject var donationViewModel: DonationViewModel
    @EnvironmentObject var squareAuthService: SquareAuthService
    @EnvironmentObject var squarePaymentService: SquarePaymentService
    @EnvironmentObject var squareReaderService: SquareReaderService
    
    @State private var isProcessing = false
    @State private var showingThankYou = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingReceiptPrompt = false
    @State private var showingEmailInput = false
    @State private var emailAddress = ""
    @State private var showingReceiptConfirmation = false
    @State private var showingSquareAuth = false
    @State private var showingReaderSelection = false
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) var dismiss
    @State private var navigateToRoot = false
    
    var body: some View {
        ZStack {
            // Background image
            if let backgroundImage = kioskStore.backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .blur(radius: 5)
            } else {
                Image("organization-image")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                    .blur(radius: 5)
            }
            
            // Dark overlay
            Color.black.opacity(0.55)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // "You'll pay:" text
                Text("You'll pay:")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                
                // Amount display
                Text(donationViewModel.formatAmount(amount))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
                
                // Square logo
                Image("square-logo-white")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    .padding(.top)

                // Reader status information
                VStack(spacing: 10) {
                    // Connection status
                    Text(squarePaymentService.connectionStatus)
                        .font(.system(size: 16))
                        .foregroundColor(squarePaymentService.isReaderConnected ? .green : .white.opacity(0.7))
                    
                    // Display available payment methods if connected
                    if squarePaymentService.isReaderConnected, !squareReaderService.availableCardInputMethods.isEmpty {
                        paymentMethodsView
                    }
                }
                .padding(.bottom)
                
                // Square reader connection button
                Button(action: {
                    // If we have readers, show reader selection sheet
                    if !squareReaderService.readers.isEmpty {
                        showingReaderSelection = true
                    } else {
                        squarePaymentService.connectToReader()
                    }
                }) {
                    HStack {
                        Image(systemName: "creditcard.wireless")
                        Text(squarePaymentService.isReaderConnected ? "Reader Connected" : "Connect Reader")
                    }
                    .padding()
                    .background(squarePaymentService.isReaderConnected ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.bottom, 15)

                // Process payment button
                Button(action: processPayment) {
                    Text(isProcessing ? "Processing..." : "Process Payment")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(25)
                }
                .disabled(isProcessing)
                .padding(.top, 10)
            }
            .padding()
            
            // Thank you overlay
            if showingThankYou {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    
                    Text("Thank You!")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Your donation has been processed.")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        // Return to home screen (all the way back to root)
                        returnToHome()
                    }) {
                        Text("Done")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 150, height: 50)
                            .background(Color.green)
                            .cornerRadius(25)
                    }
                    .padding(.top, 20)
                    .onAppear {
                        // Automatically return to home after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            returnToHome()
                        }
                    }
                }
            }

            // Receipt prompt overlay
            if showingReceiptPrompt {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image(systemName: "envelope.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Would you like a receipt?")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("We can email you a receipt for your donation.")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            // Skip receipt, show thank you
                            showingReceiptPrompt = false
                            showingThankYou = true
                        }) {
                            Text("No Thanks")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 150, height: 50)
                                .background(Color.gray.opacity(0.6))
                                .cornerRadius(25)
                        }
                        
                        Button(action: {
                            // Show email input
                            showingReceiptPrompt = false
                            showingEmailInput = true
                        }) {
                            Text("Yes, Please")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 150, height: 50)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                    }
                    .padding(.top, 20)
                }
            }

            // Email input overlay
            if showingEmailInput {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Text("Enter Your Email")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    
                    Text("We'll send your receipt to this address")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Email input field
                    TextField("email@example.com", text: $emailAddress)
                        .font(.system(size: 20))
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 30)
                        .padding(.top, 20)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            // Go back to receipt prompt
                            showingEmailInput = false
                            showingReceiptPrompt = true
                        }) {
                            Text("Back")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 50)
                                .background(Color.gray.opacity(0.6))
                                .cornerRadius(25)
                        }
                        
                        Button(action: {
                            // Show confirmation
                            if !emailAddress.isEmpty {
                                showingEmailInput = false
                                showingReceiptConfirmation = true
                            }
                        }) {
                            Text("Send Receipt")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 180, height: 50)
                                .background(emailAddress.isEmpty ? Color.blue.opacity(0.4) : Color.blue)
                                .cornerRadius(25)
                        }
                        .disabled(emailAddress.isEmpty)
                    }
                    .padding(.top, 30)
                    
                    Spacer()
                }
                .padding(.horizontal)
            }

            // Receipt confirmation overlay
            if showingReceiptConfirmation {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image(systemName: "envelope.badge.checkmark")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    
                    Text("Receipt Confirmation")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("A receipt will be sent to:\n\(emailAddress)")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: {
                        // Show thank you and then dismiss
                        showingReceiptConfirmation = false
                        showingThankYou = true
                    }) {
                        Text("Done")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 150, height: 50)
                            .background(Color.green)
                            .cornerRadius(25)
                    }
                    .padding(.top, 20)
                }
            }
            
            // Error overlay
            if showingError {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    
                    Text("Payment Failed")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(errorMessage)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button(action: {
                        // Hide error and try again
                        showingError = false
                    }) {
                        Text("Try Again")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 150, height: 50)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                    .padding(.top, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: Button(action: {
            presentationMode.wrappedValue.dismiss()
        }) {
            Image(systemName: "chevron.left")
                .foregroundColor(.white)
                .padding(8)
                .background(Circle().fill(Color.white.opacity(0.2)))
        })
        .onAppear {
            // Reset the navigation flag
            navigateToRoot = false
            
            // Check if the reader is connected
            if !squarePaymentService.isReaderConnected {
                squarePaymentService.connectToReader()
            }
        }
        .onChange(of: navigateToRoot) { _, newValue in
            if newValue {
                // Use UIKit to pop to root
                popToRootView()
            }
        }
        .sheet(isPresented: $showingSquareAuth, onDismiss: {
            // Handle dismissal if needed
        }) {
            SquareAuthorizationView()
        }
        .sheet(isPresented: $showingReaderSelection) {
            ReaderSelectionSheet()
                .environmentObject(squareReaderService)
                .environmentObject(squarePaymentService)
        }
    }
    
    // Payment methods display
    private var paymentMethodsView: some View {
        HStack(spacing: 15) {
            if squareReaderService.availableCardInputMethods.contains(.tap) {
                PaymentMethodView(iconName: "creditcard.wireless", label: "Tap")
            }
            
            if squareReaderService.availableCardInputMethods.contains(.dip) {
                PaymentMethodView(iconName: "creditcard.trianglebadge.exclamationmark", label: "Chip")
            }
            
            if squareReaderService.availableCardInputMethods.contains(.swipe) {
                PaymentMethodView(iconName: "creditcard", label: "Swipe")
            }
        }
    }
    
    private func processPayment() {
        // Check if we're authenticated with Square
        if !squareAuthService.isAuthenticated {
            showingSquareAuth = true
            return
        }
        
        // Check if a reader is connected
        if !squarePaymentService.isReaderConnected {
            squarePaymentService.connectToReader()
            return
        }
        
        isProcessing = true
        
        // Process payment through Square
        squarePaymentService.processPayment(amount: amount) { success, transactionId in
            isProcessing = false
            
            if success, let transactionId = transactionId {
                // Record the donation with the transaction ID
                donationViewModel.recordDonation(amount: amount, transactionId: transactionId)
                
                // Show receipt prompt
                showingReceiptPrompt = true
            } else {
                // Show error
                errorMessage = squarePaymentService.paymentError ?? "Payment failed"
                showingError = true
            }
        }
    }
    
    private func returnToHome() {
        // Set the flag to trigger navigation to root
        navigateToRoot = true
    }
    
    private func popToRootView() {
        // Get the key window using the newer API
        let windowScene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first
        
        let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow })
        
        // Find the root navigation controller
        if let rootViewController = keyWindow?.rootViewController {
            // Find the navigation controller
            var currentController = rootViewController
            while let presentedController = currentController.presentedViewController {
                currentController = presentedController
            }
            
            // If we found a navigation controller, pop to root
            if let navigationController = findNavigationController(viewController: currentController) {
                navigationController.popToRootViewController(animated: true)
            }
        }
    }
    
    private func findNavigationController(viewController: UIViewController?) -> UINavigationController? {
        guard let viewController = viewController else {
            return nil
        }
        
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        
        for childViewController in viewController.children {
            if let navigationController = findNavigationController(viewController: childViewController) {
                return navigationController
            }
        }
        
        return nil
    }
}

// Helper view for payment methods display
struct PaymentMethodView: View {
    let iconName: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.2))
        .cornerRadius(8)
    }
}

// Reader selection sheet
struct ReaderSelectionSheet: View {
    @EnvironmentObject var squareReaderService: SquareReaderService
    @EnvironmentObject var squarePaymentService: SquarePaymentService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if squareReaderService.readers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard.wireless.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                            .padding()
                        
                        Text("No Readers Found")
                            .font(.headline)
                        
                        Text("Connect a Square reader to process payments")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Pair New Reader") {
                            squareReaderService.startPairing()
                            dismiss()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.top)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(squareReaderService.readers, id: \.serialNumber) { reader in
                            Button(action: {
                                // Select this reader
                                squareReaderService.selectReader(reader)
                                squarePaymentService.connectToReader()
                                dismiss()
                            }) {
                                HStack {
                                    // Icon based on reader model
                                    Image(systemName: readerIconName(reader.model))
                                        .font(.system(size: 24))
                                        .foregroundColor(reader.state == .ready ? .green : .gray)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(squareReaderService.readerModelDescription(reader.model))
                                            .font(.headline)
                                        
                                        Text("S/N: \(reader.serialNumber)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    // Status indicator
                                    if reader.state == .ready {
                                        Text("Ready")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green)
                                            .cornerRadius(8)
                                    } else {
                                        Text(squareReaderService.readerStateDescription(reader.state))
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .disabled(reader.state != .ready)
                        }
                        
                        // Add button to pair a new reader
                        Section(header: Text("Add Reader")) {
                            Button(action: {
                                squareReaderService.startPairing()
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 24))
                                    Text("Pair New Reader")
                                }
                                .foregroundColor(.blue)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func readerIconName(_ model: ReaderModel) -> String {
        switch model {
        case .contactlessAndChip:
            return "creditcard.wireless"
        case .magstripe:
            return "creditcard"
        case .stand:
            return "ipad.and.iphone"
        @unknown default:
            return "questionmark.circle"
        }
    }
}
    
    private func readerModelDescription(_ model: ReaderModel) -> String {
        switch model {
        case .contactlessAndChip:
            return "Square Reader for contactless and chip"
        case .magstripe:
            return "Square Reader for magstripe"
        case .stand:
            return "Square Stand"
        @unknown default:
            return "Unknown Reader Model"
        }
    }
    
    private func readerStateDescription(_ state: ReaderState) -> String {
        switch state {
        case .connecting:
            return "Connecting"
        case .ready:
            return "Ready"
        case .disconnected:
            return "Disconnected"
        case .updatingFirmware:
            return "Updating"
        case .failedToConnect:
            return "Failed"
        @unknown default:
            return "Unknown"
        }
    }
}
