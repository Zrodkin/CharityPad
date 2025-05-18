import SwiftUI
import SquareMobilePaymentsSDK

struct ReaderManagementView: View {
    @EnvironmentObject var squareAuthService: SquareAuthService
    @StateObject var readerService: SquareReaderService
    @State private var showingReaderSettings = false
    
    init() {
        // We need to initialize the reader service with auth service, but since we don't have access to the environment object here,
        // we create it with a temporary auth service and it will be updated in onAppear
        _readerService = StateObject(wrappedValue: SquareReaderService(authService: SquareAuthService()))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            Text("Square Reader Management")
                .font(.title)
                .fontWeight(.bold)
            
            // Authentication Status
            authenticationStatusSection
            
            Divider()
            
            // Reader Management
            readersSection
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Set the correct auth service when view appears
            readerService.stopMonitoring()
            let newReaderService = SquareReaderService(authService: squareAuthService)
            _readerService = StateObject(wrappedValue: newReaderService)
            readerService.startMonitoring()
        }
        .onDisappear {
            readerService.stopMonitoring()
        }
    }
    
    // MARK: - Authentication Status Section
    
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
                    squareAuthService.startOAuthFlow()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Readers Section
    
    private var readersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Card Readers")
                .font(.headline)
            
            // Show readers list or empty state
            if readerService.readers.isEmpty {
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
        }
        .background(
            Color(UIColor.systemBackground)
                .fullScreenCover(isPresented: $showingReaderSettings) {
                    SquareReaderSettingsSheet()
                        .environmentObject(readerService)
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
            ForEach(readerService.readers, id: \.serialNumber) { reader in
                ReaderItemView(reader: reader, readerService: readerService)
            }
        }
    }
    
    private var pairingControlsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reader Pairing")
                .font(.headline)
            
            if readerService.isPairingInProgress {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 6)
                        Text(readerService.pairingStatus)
                            .font(.subheadline)
                    }
                    
                    Button("Cancel Pairing") {
                        readerService.stopPairing()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = readerService.lastPairingError {
                        Text("Error: \(error)")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(10)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Button("Pair New Reader") {
                        readerService.startPairing()
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
    @ObservedObject var readerService: SquareReaderService
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
                    Text(readerService.readerModelDescription(reader.model))
                        .font(.headline)
                    
                    // Serial number
                    Text("S/N: \(reader.serialNumber)")
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
                    batteryIcon(level: batteryStatus.level, isCharging: batteryStatus.isCharging)
                    
                    Text(readerService.batteryLevelDescription(reader))
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
                                readerService.forgetReader(reader)
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
                    Text(readerService.readerStateDescription(reader.state))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
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
        @unknown default:
            return .gray
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
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    private func batteryIcon(level: Float, isCharging: Bool) -> some View {
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
    
    private func paymentMethodsText(_ reader: ReaderInfo) -> String {
        var methods: [String] = []
        
        if reader.supportedInputMethods.contains(.tap) {
            methods.append("Tap")
        }
        if reader.supportedInputMethods.contains(.dip) {
            methods.append("Chip")
        }
        if reader.supportedInputMethods.contains(.swipe) {
            methods.append("Swipe")
        }
        
        return methods.isEmpty ? "None" : methods.joined(separator: ", ")
    }
}

struct SquareReaderSettingsSheet: View {
    @EnvironmentObject var readerService: SquareReaderService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Square Reader Settings")
                .font(.headline)
                .padding()
            
            Text("Launching Square's built-in reader management interface...")
                .multilineTextAlignment(.center)
                .padding()
            
            Button("Close") {
                dismiss()
            }
            .padding()
        }
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
                    readerService.presentReaderSettings(from: currentVC)
                    
                    // Dismiss our sheet after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ReaderManagementView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderManagementView()
            .environmentObject(SquareAuthService())
    }
}
