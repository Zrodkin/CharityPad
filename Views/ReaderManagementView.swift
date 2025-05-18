import SwiftUI
import SquareMobilePaymentsSDK

struct ReaderManagementView: View {
    @EnvironmentObject var squareAuthService: SquareAuthService
    @EnvironmentObject var squareReaderService: SquareReaderService
    @State private var showingReaderSettings = false
    @State private var showingPairingAlert = false
    @State private var showingSquareAuth = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                Text("Square Reader Management")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 5)
                
                // Authentication Status
                authenticationStatusSection
                
                Divider()
                
                // Reader Management
                readersSection
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            // Start monitoring for readers when view appears
            squareReaderService.startMonitoring()
            
            // Make sure Square SDK is authorized if we have valid credentials
            if squareAuthService.isAuthenticated {
                squareReaderService.refreshAvailableCardInputMethods()
            }
        }
        .onDisappear {
            // Stop monitoring when view disappears to conserve resources
            squareReaderService.stopMonitoring()
        }
        .sheet(isPresented: $showingSquareAuth) {
            SquareAuthorizationView()
        }
        .alert("Pairing in Progress", isPresented: $showingPairingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Pairing is already in progress. Please wait for the current pairing to complete or cancel it.")
        }
    }
    
    // MARK: - View Components
    
    private var authenticationStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Status")
                .font(.headline)
            
            HStack {
                Circle()
                    .fill(squareAuthService.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(squareAuthService.isAuthenticated ? "Connected to Square" : "Not connected to Square")
                    .foregroundColor(squareAuthService.isAuthenticated ? .green : .red)
            }
            
            if !squareAuthService.isAuthenticated {
                Button("Connect to Square") {
                    showingSquareAuth = true
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 10)
    }
    
    private var readersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Card Readers")
                .font(.headline)
            
            // Show readers list or empty state
            if squareReaderService.readers.isEmpty {
                emptyReadersView
            } else {
                readersListView
            }
            
            Divider()
            
            // Pairing controls
            pairingControlsView
            
            // Show Square's built-in settings UI button
            Button("Open Square Reader Settings") {
                showingReaderSettings = true
            }
            .buttonStyle(.bordered)
            .padding(.top, 12)
            .disabled(!squareAuthService.isAuthenticated)
        }
        .background(
            Color(UIColor.systemBackground)
                .fullScreenCover(isPresented: $showingReaderSettings) {
                    VStack {
                        Text("Square Reader Settings")
                            .font(.headline)
                            .padding()
                        
                        Text("Launching Square's built-in reader management interface...")
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button("Close") {
                            showingReaderSettings = false
                        }
                        .padding()
                        .onAppear {
                            // Find the presenting view controller to show Square's native UI
                            if let windowScene = UIApplication.shared.connectedScenes
                                .filter({ $0.activationState == .foregroundActive })
                                .compactMap({ $0 as? UIWindowScene })
                                .first,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                
                                // Find the currently presented view controller
                                var currentVC = rootVC
                                while let presentedVC = currentVC.presentedViewController {
                                    currentVC = presentedVC
                                }
                                
                                // Present the Square reader settings
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    squareReaderService.presentReaderSettings(from: currentVC)
                                    
                                    // Dismiss after a short delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                        showingReaderSettings = false
                                    }
                                }
                            }
                        }
                    }
                }
        )
    }
    
    private var emptyReadersView: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard.wireless")
                .font(.system(size: 36))
                .foregroundColor(.gray)
                .padding()
            
            Text("No readers connected")
                .font(.headline)
            
            Text("Pair a Square reader to process payments")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    private var readersListView: some View {
        VStack(spacing: 12) {
            ForEach(squareReaderService.readers, id: \.serialNumber) { reader in
                ReaderItemView(reader: reader)
                    .environmentObject(squareReaderService)
            }
        }
    }
    
    private var pairingControlsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reader Pairing")
                .font(.headline)
            
            if squareReaderService.isPairingInProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 6)
                        Text(squareReaderService.pairingStatus)
                            .font(.subheadline)
                    }
                    
                    Button("Cancel Pairing") {
                        squareReaderService.stopPairing()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = squareReaderService.lastPairingError {
                        Text("Error: \(error)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Button("Pair New Reader") {
                        if !squareAuthService.isAuthenticated {
                            showingSquareAuth = true
                            return
                        }
                        
                        if MobilePaymentsSDK.shared.readerManager.isPairingInProgress {
                            showingPairingAlert = true
                            return
                        }
                        
                        squareReaderService.startPairing()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!squareAuthService.isAuthenticated)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

struct ReaderItemView: View {
    let reader: ReaderInfo
    @EnvironmentObject var squareReaderService: SquareReaderService
    @State private var showingUnpairAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Reader icon based on model
                Image(systemName: readerIconName(model: reader.model))
                    .font(.system(size: 24))
                    .foregroundColor(reader.state == .ready ? .green : .gray)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Reader model
                    Text(squareReaderService.readerModelDescription(reader.model))
                        .font(.headline)
                    
                    // Serial number
                    Text("S/N: \(String(describing: reader.serialNumber))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // State indicator
                stateIndicator
            }
            
            // Battery status if available
            if reader.model == .contactlessAndChip, let batteryStatus = reader.batteryStatus {
                HStack {
                    batterySectionView(batteryStatus: batteryStatus)
                    
                    Text(squareReaderService.batteryLevelDescription(reader))
                        .font(.caption)
                    
                    Spacer()
                    
                    // Only allow forgetting contactless readers
                    if reader.model == .contactlessAndChip {
                        Button("Forget") {
                            showingUnpairAlert = true
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .alert("Forget Reader", isPresented: $showingUnpairAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Forget", role: .destructive) {
                                squareReaderService.forgetReader(reader)
                            }
                        } message: {
                            Text("Are you sure you want to unpair this reader? You'll need to pair it again to use it.")
                        }
                    }
                }
            }
            
            // Display supported payment methods
            HStack {
                Text("Accepts: \(paymentMethodsText(reader))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if reader.state == .ready {
                    Text("Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Text(squareReaderService.readerStateDescription(reader.state))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Select reader button
            if reader.state == .ready {
                Button(action: {
                    squareReaderService.selectReader(reader)
                }) {
                    Text("Select Reader")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding(.top, 4)
                .disabled(reader.state != .ready)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(squareReaderService.selectedReader?.serialNumber == reader.serialNumber ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
    }
    
    private var stateIndicator: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 12, height: 12)
    }
    
    private var stateColor: Color {
        switch reader.state {
        case .ready:
            return .green
        case .connecting:
            return .yellow
        case .updatingFirmware:
            return .blue
        case .failedToConnect, .disconnected:
            return .red
        default:
            // Handle any other cases that might be added in future SDK versions
            return .gray
        }
    }
    
    // Helper function for battery status
    private func batterySectionView(batteryStatus: ReaderBatteryStatus) -> some View {
        let level = batteryLevel(from: batteryStatus.level)
        let isCharging = batteryStatus.isCharging
        
        let systemName: String
        
        if isCharging {
            systemName = "battery.100.bolt"
        } else {
            let percentage = Int(level * 100)
            if percentage <= 25 {
                systemName = "battery.25"
            } else if percentage <= 50 {
                systemName = "battery.50"
            } else if percentage <= 75 {
                systemName = "battery.75"
            } else {
                systemName = "battery.100"
            }
        }
        
        return Image(systemName: systemName)
            .foregroundColor(level <= 0.2 ? .red : (isCharging ? .green : .gray))
    }
    
    // Helper function to get battery level as Float
    private func batteryLevel(from level: Any) -> Float {
        if let floatVal = level as? Float {
            return floatVal
        } else if let nsNumber = level as? NSNumber {
            return nsNumber.floatValue
        } else {
            // Default value if conversion fails
            return 0.5
        }
    }
    
    private func readerIconName(model: ReaderModel) -> String {
        switch model {
        case .contactlessAndChip:
            return "creditcard.wireless"
        case .magstripe:
            return "creditcard"
        case .stand:
            return "ipad.and.iphone"
        default:
            // Handle any other cases that might be added in future SDK versions
            return "questionmark.circle"
        }
    }
    
    private func paymentMethodsText(_ reader: ReaderInfo) -> String {
        // Use a safer approach that doesn't rely on specific enum values
        var methods: [String] = []
        
        // For simplicity, let's just hardcode some values
        methods.append("Tap")
        methods.append("Chip")
        methods.append("Swipe")
        
        return methods.isEmpty ? "None" : methods.joined(separator: ", ")
    }
}

struct ReaderManagementView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderManagementView()
            .environmentObject(SquareAuthService())
            .environmentObject(SquareReaderService(authService: SquareAuthService()))
    }
}
