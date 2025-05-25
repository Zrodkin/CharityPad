import SwiftUI

struct UpdatedCustomAmountView: View {
    @EnvironmentObject var kioskStore: KioskStore
    @Environment(\.dismiss) private var dismiss
    @State private var amountString: String = ""
    @State private var errorMessage: String? = nil
    
    // Callback for when amount is selected
    var onAmountSelected: (Double) -> Void
    
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
                Text("$\(amountString.isEmpty ? "0" : amountString)")
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
                            handleDone()
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
                        .disabled(amountString.isEmpty)
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
    }
    
    // MARK: - Helper Methods
    
    private func handleNumberPress(_ num: String) {
        // Limit the number of digits to prevent overflow or excessively long numbers
        let maxDigits = 7
        
        // Prevent adding leading zeros if the amount is already "0"
        if amountString.isEmpty && num == "0" {
            return
        }
        
        // Create a temporary string to check if the new amount would exceed the max
        let tempAmount = amountString + num
        
        // Check if the new amount would exceed the max amount
        if let amount = Double(tempAmount),
           let maxAmount = Double(kioskStore.maxAmount) {
            if amount > maxAmount {
                errorMessage = "Maximum amount is $\(Int(maxAmount))"
                return
            }
        }
        
        // Append the number if under max digits
        if amountString.count < maxDigits {
            amountString += num
        }
        
        // Clear error message when valid input is entered
        errorMessage = nil
    }
    
    private func handleDelete() {
        if !amountString.isEmpty {
            amountString.removeLast()
        }
        
        // Clear error message when deleting
        errorMessage = nil
    }
    
    private func handleDone() {
        // Convert amount to Double
        if let amount = Double(amountString), amount > 0 {
            // Check minimum amount
            if let minAmount = Double(kioskStore.minAmount), amount < minAmount {
                errorMessage = "Minimum amount is $\(Int(minAmount))"
                return
            }
            
            // Check maximum amount
            if let maxAmount = Double(kioskStore.maxAmount), amount > maxAmount {
                errorMessage = "Maximum amount is $\(Int(maxAmount))"
                return
            }
            
            // Call the callback with the selected amount
            onAmountSelected(amount)
            
            // Dismiss this view
            dismiss()
        } else {
            errorMessage = "Please enter a valid amount"
        }
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

struct UpdatedCustomAmountView_Previews: PreviewProvider {
    static var previews: some View {
        UpdatedCustomAmountView(onAmountSelected: { _ in })
            .environmentObject(KioskStore())
    }
}
