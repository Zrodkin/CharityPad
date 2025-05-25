import SwiftUI

struct DonationSelectionView: View {
    @EnvironmentObject var kioskStore: KioskStore
    @EnvironmentObject var donationViewModel: DonationViewModel
    @EnvironmentObject var squareAuthService: SquareAuthService
    @EnvironmentObject var catalogService: SquareCatalogService
    
    @State private var navigateToCustomAmount = false
    @State private var navigateToCheckout = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
            
            VStack(spacing: 10) {
                Text("Donation Amount")
                    .font(.system(size: horizontalSizeClass == .regular ? 50 : 32, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 170)
                    .padding(.bottom, 30)
                
                // Center the entire grid of buttons with a fixed width container
                VStack(spacing: 16) {
                    // Grid layout for preset amounts
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                        ForEach(0..<kioskStore.presetDonations.count, id: \.self) { index in
                            AmountButton(
                                amount: Double(kioskStore.presetDonations[index].amount) ?? 0,
                                isSynced: kioskStore.presetDonations[index].isSync,
                                action: {
                                    let donationAmount = Double(kioskStore.presetDonations[index].amount) ?? 0
                                    donationViewModel.selectedAmount = donationAmount
                                    donationViewModel.isCustomAmount = false
                                    navigateToCheckout = true
                                }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Custom amount button
                    if kioskStore.allowCustomAmount {
                        Button(action: {
                            donationViewModel.isCustomAmount = true
                            navigateToCustomAmount = true
                        }) {
                            Text("Custom")
                                .font(.system(size: horizontalSizeClass == .regular ? 24 : 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: horizontalSizeClass == .regular ? 80 : 60)
                                .background(Color.white.opacity(0.3))
                                .cornerRadius(15)
                        }
                        .padding(.top, 10)
                    }
                }
                // Limit the width of the button container
                .frame(maxWidth: horizontalSizeClass == .regular ? 800 : 500)
                .padding(.horizontal, 20)
                
                // Status indicator for Square
                if squareAuthService.isAuthenticated {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected to Square")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 20)
                }
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            // Fetch donation items from catalog if authenticated
            if squareAuthService.isAuthenticated {
                // Connect kioskStore to catalog service
                kioskStore.connectCatalogService(catalogService)
                
                // Load preset donations from catalog
                kioskStore.loadPresetDonationsFromCatalog()
            }
            
            // Make sure donation view model is updated with current preset amounts
            updateDonationViewModel()
        }
        // Navigation destination for Custom Amount
        .navigationDestination(isPresented: $navigateToCustomAmount) {
            UpdatedCustomAmountView(onAmountSelected: { amount in
                donationViewModel.selectedAmount = amount
                donationViewModel.isCustomAmount = true
                navigateToCheckout = true
            })
        }
        // Navigation destination for Checkout
        .navigationDestination(isPresented: $navigateToCheckout) {
            UpdatedCheckoutView(
                amount: donationViewModel.selectedAmount ?? 0,
                isCustomAmount: donationViewModel.isCustomAmount,
                onDismiss: {
                    // When CheckoutView is dismissed, set navigateToCheckout to false
                    // to return to this view
                    navigateToCheckout = false
                }
            )
        }
    }
    
    // Update the donation view model with current preset amounts
    private func updateDonationViewModel() {
        let amounts = kioskStore.presetDonations.compactMap { Double($0.amount) }
        if !amounts.isEmpty {
            donationViewModel.presetAmounts = amounts
        }
    }
}

// Enhanced amount button that shows sync status
struct AmountButton: View {
    let amount: Double
    let isSynced: Bool
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Button background
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.3))
                
                // Button content
                VStack(spacing: 4) {
                    Text("$\(Int(amount))")
                        .font(.system(size: horizontalSizeClass == .regular ? 24 : 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // Show sync indicator for admins (not visible in actual kiosk mode)
                    if isSynced {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(height: horizontalSizeClass == .regular ? 80 : 60)
        }
        .padding(.horizontal, 0)
    }
}

struct DonationSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        DonationSelectionView()
            .environmentObject(KioskStore())
            .environmentObject(DonationViewModel())
            .environmentObject(SquareAuthService())
            .environmentObject(SquareCatalogService(authService: SquareAuthService()))
    }
}
