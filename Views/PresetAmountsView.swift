import SwiftUI

struct PresetAmountsView: View {
    @EnvironmentObject private var kioskStore: KioskStore
    @State private var presetAmounts: [PresetAmount] = []
    @State private var allowCustomAmount: Bool = true
    @State private var minAmount: String = "1"
    @State private var maxAmount: String = "100000"
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var showToast = false
    
    // Define columns for the grid layout
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    // Background gradient colors
    private let gradientColors = [
        Color(red: 0.55, green: 0.47, blue: 0.84),
        Color(red: 0.56, green: 0.71, blue: 1.0),
        Color(red: 0.97, green: 0.76, blue: 0.63),
        Color(red: 0.97, green: 0.42, blue: 0.42)
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Unsaved changes badge
                unsavedChangesBadge
                
                // Two column layout for iPad
                HStack(alignment: .top, spacing: 20) {
                    // Left column - Preset Amounts
                    presetAmountsColumn
                    
                    // Right column - Amount Limits
                    amountLimitsColumn
                }
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .onAppear {
                loadSettings()
            }
            .overlay(toastOverlay)
            .navigationTitle("Preset Amounts")
        }
    }
    
    // MARK: - View Components
    
    private var unsavedChangesBadge: some View {
        Group {
            if isDirty {
                HStack {
                    Spacer()
                    Text("Unsaved changes")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.orange, lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private var presetAmountsColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Preset Amounts")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Set up to 6 preset donation amounts.")
                .foregroundColor(.gray)
            
            VStack(spacing: 15) {
                ForEach(presetAmounts.indices, id: \.self) { index in
                    presetAmountRow(for: index)
                }
                
                addAmountButton
                
                Text("These amounts will be displayed as buttons on the donation screen.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
            }
            .padding()
            .background(Color.white.opacity(0.85))
            .cornerRadius(15)
        }
    }
    
    private func presetAmountRow(for index: Int) -> some View {
        HStack {
            HStack {
                Text("$")
                    .foregroundColor(.gray)
                
                TextField("Amount", text: $presetAmounts[index].amount)
                    .keyboardType(.numberPad)
                    .onChange(of: presetAmounts[index].amount) { _, _ in
                        isDirty = true
                    }
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            Button(action: {
                if presetAmounts.count > 1 {
                    presetAmounts.remove(at: index)
                    isDirty = true
                }
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .disabled(presetAmounts.count <= 1)
        }
    }
    
    private var addAmountButton: some View {
        Group {
            if presetAmounts.count < 6 {
                Button(action: {
                    presetAmounts.append(PresetAmount(id: UUID().uuidString, amount: ""))
                    isDirty = true
                }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Amount Option")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private var amountLimitsColumn: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Amount Limits")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 20) {
                // Allow custom amount toggle
                customAmountToggle
                
                // Min and max amount
                amountLimitsRow
                
                Text(allowCustomAmount ? "These limits will be applied when donors enter custom amounts." : "Custom amounts are disabled. Donors can only select from preset options.")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Save button
                saveButton
            }
            .padding()
            .background(Color.white.opacity(0.85))
            .cornerRadius(15)
        }
    }
    
    private var customAmountToggle: some View {
        HStack {
            Toggle("Allow donors to enter custom amounts", isOn: $allowCustomAmount)
                .onChange(of: allowCustomAmount) { _, _ in
                    isDirty = true
                }
            
            Button(action: {}) {
                Image(systemName: "info.circle")
                    .foregroundColor(.gray)
            }
            .help("When enabled, donors can enter their own amount instead of using preset options")
        }
    }
    
    private var amountLimitsRow: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Minimum Amount")
                    .font(.headline)
                
                HStack {
                    Text("$")
                        .foregroundColor(.gray)
                    
                    TextField("Min", text: $minAmount)
                        .keyboardType(.numberPad)
                        .disabled(!allowCustomAmount)
                        .onChange(of: minAmount) { _, _ in
                            isDirty = true
                        }
                }
                .padding(10)
                .background(allowCustomAmount ? Color.white : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text("Maximum Amount")
                    .font(.headline)
                
                HStack {
                    Text("$")
                        .foregroundColor(.gray)
                    
                    TextField("Max", text: $maxAmount)
                        .keyboardType(.numberPad)
                        .disabled(!allowCustomAmount)
                        .onChange(of: maxAmount) { _, _ in
                            isDirty = true
                        }
                }
                .padding(10)
                .background(allowCustomAmount ? Color.white : Color.gray.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
    
    private var saveButton: some View {
        HStack {
            Spacer()
            
            Button(action: saveSettings) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.trailing, 5)
                        Text("Saving...")
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .padding(.trailing, 5)
                        Text("Save Changes")
                    }
                }
                .padding()
                .background(isDirty ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!isDirty || isSaving)
        }
    }
    
    private var toastOverlay: some View {
        Group {
            if showToast {
                ToastView(message: "Settings saved successfully")
                    .transition(.move(edge: .top))
                    .animation(.spring(), value: showToast)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showToast = false
                        }
                    }
            }
        }
    }
    
    // MARK: - Functions
    
    func loadSettings() {
        // Convert string array to PresetAmount objects
        presetAmounts = kioskStore.presetAmounts.map { PresetAmount(id: UUID().uuidString, amount: $0) }
        allowCustomAmount = kioskStore.allowCustomAmount
        minAmount = kioskStore.minAmount
        maxAmount = kioskStore.maxAmount
    }
    
    func saveSettings() {
        isSaving = true
        
        // Update the store
        kioskStore.presetAmounts = presetAmounts.map { $0.amount }
        kioskStore.allowCustomAmount = allowCustomAmount
        kioskStore.minAmount = minAmount
        kioskStore.maxAmount = maxAmount
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            kioskStore.saveSettings()
            isSaving = false
            isDirty = false
            showToast = true
        }
    }
}

struct PresetAmount: Identifiable {
    var id: String
    var amount: String
}

struct PresetAmountsView_Previews: PreviewProvider {
    static var previews: some View {
        PresetAmountsView()
            .environmentObject(KioskStore())
    }
}
