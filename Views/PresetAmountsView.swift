import SwiftUI

struct UpdatedPresetAmountsView: View {
    @EnvironmentObject private var kioskStore: KioskStore
    @EnvironmentObject private var squareAuthService: SquareAuthService
    @EnvironmentObject private var catalogService: SquareCatalogService
    
    @State private var allowCustomAmount: Bool = true
    @State private var minAmount: String = "1"
    @State private var maxAmount: String = "100000"
    @State private var isDirty = false
    @State private var isSaving = false
    @State private var showToast = false
    @State private var toastMessage = "Settings saved successfully"
    @State private var showingAuthSheet = false
    
    // State for adding new amount
    @State private var showingAddAmountSheet = false
    @State private var newAmountString = ""
    
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
                
                // Square connection status
                squareConnectionStatus
                
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
                
                // Connect catalog service to kiosk store
                kioskStore.connectCatalogService(catalogService)
                
                // Fetch donations from catalog if authenticated
                if squareAuthService.isAuthenticated {
                    catalogService.fetchPresetDonations()
                }
            }
            .onChange(of: squareAuthService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    // Refresh when authentication changes
                    catalogService.fetchPresetDonations()
                }
            }
            .overlay(toastOverlay)
            .navigationTitle("Preset Amounts")
            .sheet(isPresented: $showingAuthSheet) {
                SquareAuthorizationView()
            }
            .sheet(isPresented: $showingAddAmountSheet) {
                addAmountSheet
            }
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
    
    private var squareConnectionStatus: some View {
        Group {
            HStack {
                Circle()
                    .fill(squareAuthService.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(squareAuthService.isAuthenticated ?
                     "Connected to Square" :
                     "Not connected to Square")
                    .foregroundColor(squareAuthService.isAuthenticated ? .green : .red)
                
                Spacer()
                
                if !squareAuthService.isAuthenticated {
                    Button("Connect") {
                        showingAuthSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                } else if kioskStore.isSyncingWithCatalog {
                    // Show sync indicator
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                        
                        Text("Syncing...")
                            .font(.caption)
                    }
                } else if let lastSyncTime = kioskStore.lastSyncTime {
                    // Show last sync time
                    Text("Last synced: \(formatDate(lastSyncTime))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color.white.opacity(0.85))
            .cornerRadius(15)
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
                // Preset donation amounts list
                ForEach(Array(kioskStore.presetDonations.enumerated()), id: \.offset) { index, donation in
                    presetDonationRow(for: index, donation: donation)
                }
                
                addAmountButton
                
                // Info text
                Group {
                    if squareAuthService.isAuthenticated {
                        Text("Preset amounts will be synchronized with your Square catalog and displayed in the donation screen.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Connect to Square to sync preset amounts with your catalog.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 10)
                
                // Error message if any
                if let error = kioskStore.lastSyncError {
                    Text("Sync error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 5)
                }
            }
            .padding()
            .background(Color.white.opacity(0.85))
            .cornerRadius(15)
        }
    }
    
    private func presetDonationRow(for index: Int, donation: PresetDonation) -> some View {
        HStack {
            HStack {
                Text("$")
                    .foregroundColor(.gray)
                
                TextField("Amount", text: Binding(
                    get: { donation.amount },
                    set: { newValue in
                        kioskStore.updatePresetDonation(at: index, amount: newValue)
                        isDirty = true
                    }
                ))
                .keyboardType(.numberPad)
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // Sync status indicator
            Group {
                if donation.isSync {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help("Synced with Square catalog")
                } else if squareAuthService.isAuthenticated {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .help("Not synced with Square catalog")
                }
            }
            
            Button(action: {
                kioskStore.removePresetDonation(at: index)
                isDirty = true
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
            .disabled(kioskStore.presetDonations.count <= 1)
        }
    }
    
    private var addAmountButton: some View {
        Group {
            if kioskStore.presetDonations.count < 6 {
                Button(action: {
                    showingAddAmountSheet = true
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
                HStack {
                    Spacer()
                    
                    Button(action: saveSettings) {
                        HStack {
                            if isSaving || kioskStore.isSyncingWithCatalog {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 5)
                                Text(kioskStore.isSyncingWithCatalog ? "Syncing..." : "Saving...")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .padding(.trailing, 5)
                                Text("Save Changes")
                            }
                        }
                        .padding()
                        .background(isDirty && !isSaving && !kioskStore.isSyncingWithCatalog ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(!isDirty || isSaving || kioskStore.isSyncingWithCatalog)
                }
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
    
    private var toastOverlay: some View {
        Group {
            if showToast {
                ToastView(message: toastMessage)
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
    
    private var addAmountSheet: some View {
        VStack(spacing: 20) {
            Text("Add Preset Amount")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                Text("$")
                    .font(.title)
                    .foregroundColor(.gray)
                
                TextField("Amount", text: $newAmountString)
                    .font(.title)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button("Cancel") {
                    newAmountString = ""
                    showingAddAmountSheet = false
                }
                .buttonStyle(.bordered)
                
                Button("Add") {
                    if let amount = Double(newAmountString), amount > 0 {
                        kioskStore.addPresetDonation(amount: newAmountString)
                        isDirty = true
                        showingAddAmountSheet = false
                        newAmountString = ""
                    } else {
                        // Show invalid amount error
                        toastMessage = "Please enter a valid amount"
                        showToast = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newAmountString.isEmpty || Double(newAmountString) == nil)
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - Functions
    
    func loadSettings() {
        // Copy data from kioskStore to local state
        allowCustomAmount = kioskStore.allowCustomAmount
        minAmount = kioskStore.minAmount
        maxAmount = kioskStore.maxAmount
        isDirty = false
    }
    
    func saveSettings() {
        isSaving = true
        
        // Update the store
        kioskStore.allowCustomAmount = allowCustomAmount
        kioskStore.minAmount = minAmount
        kioskStore.maxAmount = maxAmount
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            kioskStore.saveSettings() // This will also trigger the catalog sync
            isSaving = false
            isDirty = false
            toastMessage = "Settings saved successfully"
            showToast = true
        }
    }
    
    /// Format a date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct UpdatedPresetAmountsView_Previews: PreviewProvider {
    static var previews: some View {
        UpdatedPresetAmountsView()
            .environmentObject(KioskStore())
            .environmentObject(SquareAuthService())
            .environmentObject(SquareCatalogService(authService: SquareAuthService()))
    }
}
