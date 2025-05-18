import Foundation
import SwiftUI
import SquareMobilePaymentsSDK

// Note: Remove any custom ReaderModel or ReaderState enums since they're already defined by the SDK

class SquareReaderService: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var readers: [ReaderInfo] = []
    @Published var isPairingInProgress = false
    @Published var pairingStatus: String = "Not Started"
    @Published var lastPairingError: String? = nil
    @Published var selectedReader: ReaderInfo? = nil
    @Published var availableCardInputMethods: CardInputMethods = []
    
    // Private properties
    private var pairingHandle: PairingHandle? = nil
    private let authService: SquareAuthService
    
    init(authService: SquareAuthService) {
        self.authService = authService
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring for reader updates
    func startMonitoring() {
        // Add this class as an observer to receive reader updates
        MobilePaymentsSDK.shared.readerManager.add(self)
        MobilePaymentsSDK.shared.paymentManager.add(self)
        
        // Update initial readers list
        refreshReaders()
        
        // Update available card input methods
        refreshAvailableCardInputMethods()
    }
    
    /// Stop monitoring for reader updates
    func stopMonitoring() {
        MobilePaymentsSDK.shared.readerManager.remove(self)
        MobilePaymentsSDK.shared.paymentManager.remove(self)
    }
    
    /// Start pairing process for Square readers
    func startPairing() {
        // Ensure SDK is authorized first
        guard MobilePaymentsSDK.shared.authorizationManager.state == .authorized else {
            pairingStatus = "Square SDK not authorized"
            lastPairingError = "Please authorize the Square SDK first"
            return
        }
        
        // Check if pairing is already in progress
        guard !MobilePaymentsSDK.shared.readerManager.isPairingInProgress else {
            pairingStatus = "Pairing already in progress"
            return
        }
        
        // Reset state
        lastPairingError = nil
        isPairingInProgress = true
        pairingStatus = "Searching for readers..."
        
        // Start pairing process
        pairingHandle = MobilePaymentsSDK.shared.readerManager.startPairing(with: self)
    }
    
    /// Stop the pairing process
    func stopPairing() {
        pairingHandle?.stop()
        pairingHandle = nil
        isPairingInProgress = false
        pairingStatus = "Pairing cancelled"
    }
    
    /// Forget/unpair a reader
    func forgetReader(_ reader: ReaderInfo) {
        MobilePaymentsSDK.shared.readerManager.forget(reader)
    }
    
    /// Select a reader to use for payments
    func selectReader(_ reader: ReaderInfo) {
        // Only select readers that are in ready state
        if reader.state == .ready {
            selectedReader = reader
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    /// Present the built-in Square reader settings UI
    func presentReaderSettings(from viewController: UIViewController) {
        MobilePaymentsSDK.shared.settingsManager.presentSettings(from: viewController) { _ in
            // Handle dismissal if needed
            self.refreshReaders()
        }
    }
    
    // MARK: - Helper Methods
    
    /// Check if a specific card input method is available
    func hasCardInputMethod(_ method: CardInputMethod) -> Bool {
        return availableCardInputMethods.contains(method)
    }
    
    /// Get battery level description
    func batteryLevelDescription(_ reader: ReaderInfo) -> String {
        guard let batteryStatus = reader.batteryStatus else {
            return "N/A"
        }
        
        let percentage = Int(batteryStatus.level * 100)
        let chargingStatus = batteryStatus.isCharging ? " (Charging)" : ""
        
        return "\(percentage)%\(chargingStatus)"
    }
    
    /// Get a descriptive text for reader state
    func readerStateDescription(_ state: ReaderState) -> String {
        switch state {
        case .connecting:
            return "Connecting..."
        case .ready:
            return "Ready"
        case .disconnected:
            return "Disconnected"
        case .updatingFirmware:
            return "Updating Firmware..."
        case .failedToConnect:
            return "Failed to Connect"
        @unknown default:
            return "Unknown State"
        }
    }
    
    /// Get a descriptive text for reader model
    func readerModelDescription(_ model: ReaderModel) -> String {
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
    
    /// Get a string description of available payment methods
    func paymentMethodsDescription(_ methods: CardInputMethods) -> String {
        var descriptions: [String] = []
        
        if methods.contains(.tap) {
            descriptions.append("contactless")
        }
        if methods.contains(.dip) {
            descriptions.append("chip")
        }
        if methods.contains(.swipe) {
            descriptions.append("swipe")
        }
        
        return descriptions.isEmpty ? "None" : descriptions.joined(separator: ", ")
    }
    
    // MARK: - Private Methods
    
    /// Refresh the list of available readers
    private func refreshReaders() {
        DispatchQueue.main.async {
            self.readers = MobilePaymentsSDK.shared.readerManager.readers
            
            // If we have an available reader and none is selected, select the first ready one
            if self.selectedReader == nil && !self.readers.isEmpty {
                self.selectedReader = self.readers.first(where: { $0.state == .ready })
            }
            
            // If the currently selected reader is not ready anymore, try to find another ready reader
            if let selectedReader = self.selectedReader, selectedReader.state != .ready {
                self.selectedReader = self.readers.first(where: { $0.state == .ready })
            }
            
            self.objectWillChange.send()
        }
    }
    
    /// Refresh the available card input methods
    private func refreshAvailableCardInputMethods() {
        DispatchQueue.main.async {
            self.availableCardInputMethods = MobilePaymentsSDK.shared.paymentManager.availableCardInputMethods
            self.objectWillChange.send()
        }
    }
}

// MARK: - ReaderPairingDelegate
extension SquareReaderService: ReaderPairingDelegate {
    func readerPairingDidBegin() {
        DispatchQueue.main.async {
            self.pairingStatus = "Searching for nearby readers..."
            self.isPairingInProgress = true
            self.lastPairingError = nil
            self.objectWillChange.send()
        }
    }
    
    func readerPairingDidSucceed() {
        DispatchQueue.main.async {
            self.pairingStatus = "Reader paired successfully!"
            self.isPairingInProgress = false
            self.pairingHandle = nil
            
            // Refresh readers list
            self.refreshReaders()
            self.objectWillChange.send()
        }
    }
    
    func readerPairingDidFail(with error: Error) {
        DispatchQueue.main.async {
            self.pairingStatus = "Pairing failed"
            self.lastPairingError = error.localizedDescription
            self.isPairingInProgress = false
            self.pairingHandle = nil
            self.objectWillChange.send()
        }
    }
}

// MARK: - ReaderObserver
extension SquareReaderService: ReaderObserver {
    func readerWasAdded(_ readerInfo: ReaderInfo) {
        refreshReaders()
    }
    
    func readerWasRemoved(_ readerInfo: ReaderInfo) {
        DispatchQueue.main.async {
            self.refreshReaders()
            
            // If the removed reader was selected, clear selection
            if let selectedReader = self.selectedReader, selectedReader.serialNumber == readerInfo.serialNumber {
                self.selectedReader = nil
            }
            
            self.objectWillChange.send()
        }
    }
    
    func readerDidChange(_ readerInfo: ReaderInfo, change: ReaderChange) {
        DispatchQueue.main.async {
            // Update readers list for any change
            self.refreshReaders()
            
            // If the state changed for our selected reader, update available card input methods
            if change == .stateDidChange,
               let selectedReader = self.selectedReader,
               selectedReader.serialNumber == readerInfo.serialNumber {
                self.refreshAvailableCardInputMethods()
            }
            
            self.objectWillChange.send()
        }
    }
}

// MARK: - AvailableCardInputMethodsObserver
extension SquareReaderService: AvailableCardInputMethodsObserver {
    func availableCardInputMethodsDidChange(_ cardInputMethods: CardInputMethods) {
        DispatchQueue.main.async {
            self.availableCardInputMethods = cardInputMethods
            self.objectWillChange.send()
        }
    }
}
