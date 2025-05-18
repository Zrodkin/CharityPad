import SwiftUI

struct DonationSelectionView: View {
    @EnvironmentObject var kioskStore: KioskStore
    @EnvironmentObject var donationViewModel: DonationViewModel
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
                        ForEach(0..<donationViewModel.presetAmounts.count, id: \.self) { index in
                            AmountButton(amount: donationViewModel.presetAmounts[index]) {
                                donationViewModel.selectedAmount = donationViewModel.presetAmounts[index]
                                donationViewModel.isCustomAmount = false
                                navigateToCheckout = true
                            }
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
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        // Navigation destination for Custom Amount
        .navigationDestination(isPresented: $navigateToCustomAmount) {
            CustomAmountView()
        }
        // Navigation destination for Checkout
        .navigationDestination(isPresented: $navigateToCheckout) {
            CheckoutView(amount: donationViewModel.selectedAmount ?? 0)
        }
    }
}

struct AmountButton: View {
    let amount: Double
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Button(action: action) {
            Text("$\(Int(amount))") // Displaying amount as Int for cleaner UI
                .font(.system(size: horizontalSizeClass == .regular ? 24 : 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: horizontalSizeClass == .regular ? 80 : 60)
                .background(Color.white.opacity(0.3))
                .cornerRadius(15)
        }
        .padding(.horizontal, 0)
    }
}
