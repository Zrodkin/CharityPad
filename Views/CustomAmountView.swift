import SwiftUI

struct CustomAmountView: View {
    @EnvironmentObject var kioskStore: KioskStore
    @EnvironmentObject var donationViewModel: DonationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var navigateToCheckout = false
    @State private var errorMessage: String? = nil
    
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
            
            VStack(spacing: 20) {
                // Amount display
                Text("$\(donationViewModel.customAmount)")
                    .font(.system(size: 65, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 120)
                    .padding(.bottom, 10)
                
                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.7))
                        .cornerRadius(10)
                }
                
                // Keypad
                VStack(spacing: 12) {
                    // Row 1
                    HStack(spacing: 12) {
                        ForEach(1...3, id: \.self) { num in
                            KeypadButton(number: num, letters: num == 2 ? "ABC" : num == 3 ? "DEF" : "") {
                                handleNumberPress(String(num))
                            }
                        }
                    }
                    
                    // Row 2
                    HStack(spacing: 12) {
                        ForEach(4...6, id: \.self) { num in
                            KeypadButton(number: num, letters: num == 4 ? "GHI" : num == 5 ? "JKL" : "MNO") {
                                handleNumberPress(String(num))
                            }
                        }
                    }
                    
                    // Row 3
                    HStack(spacing: 12) {
                        ForEach(7...9, id: \.self) { num in
                            KeypadButton(number: num, letters: num == 7 ? "PQRS" : num == 8 ? "TUV" : "WXYZ") {
                                handleNumberPress(String(num))
                            }
                        }
                    }
                    
                    // Row 4
                    HStack(spacing: 12) {
                        // Delete button
                        Button(action: handleDelete) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 64)
                                
                                Image(systemName: "delete.left")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // 0 button
                        KeypadButton(number: 0, letters: "") {
                            handleNumberPress("0")
                        }
                        
                        // Next button
                        Button(action: {
                            // Ensure customAmount can be converted to a Double and is within min/max range
                            if let amount = Double(donationViewModel.customAmount),
                               let minAmount = Double(kioskStore.minAmount),
                               let maxAmount = Double(kioskStore.maxAmount) {
                                
                                if amount < minAmount {
                                    errorMessage = "Minimum amount is $\(Int(minAmount))"
                                    return
                                }
                                
                                if amount > maxAmount {
                                    errorMessage = "Maximum amount is $\(Int(maxAmount))"
                                    return
                                }
                                
                                donationViewModel.selectedAmount = amount
                                navigateToCheckout = true
                            }
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 64)
                                
                                Image(systemName: "arrow.forward")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: 800)
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                }
            }
        }
        .navigationDestination(isPresented: $navigateToCheckout) {
            CheckoutView(
                amount: Double(donationViewModel.customAmount) ?? 0,
                onDismiss: {
                    // When CheckoutView is dismissed, set navigateToCheckout to false
                    // to return to this view
                    navigateToCheckout = false
                }
            )
        }
    }
    
    private func handleNumberPress(_ num: String) {
        // Limit the number of digits to prevent overflow or excessively long numbers
        let maxDigits = 7
        
        // Prevent adding leading zeros if the amount is already "0"
        if donationViewModel.customAmount == "0" && num == "0" {
            return
        }
        
        // Create a temporary string to check if the new amount would exceed the max
        let tempAmount: String
        if donationViewModel.customAmount == "0" {
            tempAmount = num
        } else {
            tempAmount = donationViewModel.customAmount + num
        }
        
        // Check if the new amount would exceed the max amount
        if let amount = Double(tempAmount),
           let maxAmount = Double(kioskStore.maxAmount) {
            if amount > maxAmount {
                errorMessage = "Maximum amount is $\(Int(maxAmount))"
                return
            }
        }
        
        // If current amount is "0", replace it with the new number (unless it's "0" again)
        if donationViewModel.customAmount == "0" {
            donationViewModel.customAmount = num
        } else if donationViewModel.customAmount.count < maxDigits {
            // Append the number if under max digits
            donationViewModel.customAmount += num
        }
        
        // Clear error message when valid input is entered
        errorMessage = nil
    }
    
    private func handleDelete() {
        if donationViewModel.customAmount.count > 1 {
            donationViewModel.customAmount.removeLast()
        } else {
            // If only one digit is left, or it's already "0", set to "0"
            donationViewModel.customAmount = "0"
        }
        
        // Clear error message when deleting
        errorMessage = nil
    }
}

struct KeypadButton: View {
    let number: Int
    let letters: String // Sub-text for the button (e.g., "ABC" for 2)
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(number)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                if !letters.isEmpty {
                    Text(letters)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity) // Make button take available width
            .frame(height: 64) // Fixed height for the button
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2)) // Semi-transparent background
            )
        }
    }
}
