
import Foundation
import Combine
import SwiftUI

/// Preset donation amount with Square catalog ID
struct PresetDonation: Identifiable, Equatable, Codable {
    var id: String
    var amount: String
    var catalogItemId: String?
    var isSync: Bool
    
    static func == (lhs: PresetDonation, rhs: PresetDonation) -> Bool {
        return lhs.id == rhs.id && lhs.amount == rhs.amount && lhs.catalogItemId == rhs.catalogItemId
    }
}

class KioskStore: ObservableObject {
    // MARK: - Published Properties
    
    @Published var headline: String = "Tap to Donate"
    @Published var subtext: String = "Support our mission with your generous donation"
    @Published var backgroundImage: UIImage?
    @Published var logoImage: UIImage?
    @Published var presetDonations: [PresetDonation] = []
    @Published var allowCustomAmount: Bool = true
    @Published var minAmount: String = "1"
    @Published var maxAmount: String = "100000"
    @Published var timeoutDuration: String = "60"
    @Published var homePageEnabled: Bool = true
    
    // MARK: - Catalog Sync State
    @Published var isSyncingWithCatalog: Bool = false
    @Published var lastSyncError: String? = nil
    @Published var lastSyncTime: Date? = nil
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var catalogService: SquareCatalogService?
    
    // MARK: - Initialization
    
    init() {
        loadFromUserDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Connect to the catalog service for sync operations
    func connectCatalogService(_ service: SquareCatalogService) {
        self.catalogService = service
        
        // Set up publishers to monitor catalog service changes
        service.$isLoading
            .assign(to: \.isSyncingWithCatalog, on: self)
            .store(in: &cancellables)
        
        service.$error
            .assign(to: \.lastSyncError, on: self)
            .store(in: &cancellables)
    }
    
    /// Load settings from UserDefaults
    func loadFromUserDefaults() {
        if let headline = UserDefaults.standard.string(forKey: "kioskHeadline") {
            self.headline = headline
        }
        
        if let subtext = UserDefaults.standard.string(forKey: "kioskSubtext") {
            self.subtext = subtext
        }
        
        // Load preset donations
        if let presetDonationsData = UserDefaults.standard.data(forKey: "kioskPresetDonations") {
            do {
                let decoder = JSONDecoder()
                self.presetDonations = try decoder.decode([PresetDonation].self, from: presetDonationsData)
            } catch {
                print("Failed to decode preset donations: \(error)")
                
                // Fallback to legacy presetAmounts format
                if let presetAmountsData = UserDefaults.standard.array(forKey: "kioskPresetAmounts") as? [String] {
                    self.presetDonations = presetAmountsData.map { amount in
                        PresetDonation(
                            id: UUID().uuidString,
                            amount: amount,
                            catalogItemId: nil,
                            isSync: false
                        )
                    }
                }
            }
        } else if let presetAmountsData = UserDefaults.standard.array(forKey: "kioskPresetAmounts") as? [String] {
            // Legacy support - migrate from old format
            self.presetDonations = presetAmountsData.map { amount in
                PresetDonation(
                    id: UUID().uuidString,
                    amount: amount,
                    catalogItemId: nil,
                    isSync: false
                )
            }
        }
        
        self.allowCustomAmount = UserDefaults.standard.bool(forKey: "kioskAllowCustomAmount")
        
        if let minAmount = UserDefaults.standard.string(forKey: "kioskMinAmount") {
            self.minAmount = minAmount
        }
        
        if let maxAmount = UserDefaults.standard.string(forKey: "kioskMaxAmount") {
            self.maxAmount = maxAmount
        }
        
        if let timeoutDuration = UserDefaults.standard.string(forKey: "kioskTimeoutDuration") {
            self.timeoutDuration = timeoutDuration
        }
        
        // Load homePageEnabled state
        self.homePageEnabled = UserDefaults.standard.bool(forKey: "kioskHomePageEnabled")
        
        // Load images if they exist
        if let logoImageData = UserDefaults.standard.data(forKey: "kioskLogoImage") {
            self.logoImage = UIImage(data: logoImageData)
        }
        
        if let backgroundImageData = UserDefaults.standard.data(forKey: "kioskBackgroundImage") {
            self.backgroundImage = UIImage(data: backgroundImageData)
        }
        
        // Load sync state
        if let lastSyncTimeInterval = UserDefaults.standard.object(forKey: "kioskLastSyncTime") as? TimeInterval {
            self.lastSyncTime = Date(timeIntervalSince1970: lastSyncTimeInterval)
        }
    }
    
    /// Save settings to UserDefaults
    func saveToUserDefaults() {
        UserDefaults.standard.set(headline, forKey: "kioskHeadline")
        UserDefaults.standard.set(subtext, forKey: "kioskSubtext")
        
        // Save preset donations in new format
        do {
            let encoder = JSONEncoder()
            let presetDonationsData = try encoder.encode(presetDonations)
            UserDefaults.standard.set(presetDonationsData, forKey: "kioskPresetDonations")
            
            // Also save in legacy format for backwards compatibility
            let amountsOnly = presetDonations.map { $0.amount }
            UserDefaults.standard.set(amountsOnly, forKey: "kioskPresetAmounts")
        } catch {
            print("Failed to encode preset donations: \(error)")
            
            // Fallback to legacy format
            let amountsOnly = presetDonations.map { $0.amount }
            UserDefaults.standard.set(amountsOnly, forKey: "kioskPresetAmounts")
        }
        
        UserDefaults.standard.set(allowCustomAmount, forKey: "kioskAllowCustomAmount")
        UserDefaults.standard.set(minAmount, forKey: "kioskMinAmount")
        UserDefaults.standard.set(maxAmount, forKey: "kioskMaxAmount")
        UserDefaults.standard.set(timeoutDuration, forKey: "kioskTimeoutDuration")
        UserDefaults.standard.set(homePageEnabled, forKey: "kioskHomePageEnabled")
        
        // Save logo image or remove it if nil
        if let logoImage = logoImage, let logoData = logoImage.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(logoData, forKey: "kioskLogoImage")
        } else {
            UserDefaults.standard.removeObject(forKey: "kioskLogoImage")
        }
        
        // Save background image
        if let backgroundImage = backgroundImage, let backgroundData = backgroundImage.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(backgroundData, forKey: "kioskBackgroundImage")
        } else {
            UserDefaults.standard.removeObject(forKey: "kioskBackgroundImage")
        }
        
        // Save sync state
        if let lastSyncTime = lastSyncTime {
            UserDefaults.standard.set(lastSyncTime.timeIntervalSince1970, forKey: "kioskLastSyncTime")
        } else {
            UserDefaults.standard.removeObject(forKey: "kioskLastSyncTime")
        }
    }
    
    /// Save all settings, including syncing to Square catalog if connected
    func saveSettings() {
        saveToUserDefaults()
        
        // If catalog service is connected, sync preset amounts
        if let catalogService = catalogService {
            syncPresetAmountsWithCatalog(using: catalogService)
        }
        
        // In a real app, you might want to sync with a server here
        NotificationCenter.default.post(name: Notification.Name("KioskSettingsUpdated"), object: nil)
    }
    
    /// Sync preset donation amounts with Square catalog
    func syncPresetAmountsWithCatalog(using service: SquareCatalogService) {
        isSyncingWithCatalog = true
        lastSyncError = nil
        
        // Extract amounts as doubles
        let amountValues = presetDonations.compactMap { Double($0.amount) }
        
        // Only sync if we have valid amounts
        if !amountValues.isEmpty {
            service.savePresetDonations(amounts: amountValues)
            
            // Update sync status
            lastSyncTime = Date()
            saveToUserDefaults()
            
            // Start watching for catalog service changes
            service.$presetDonations
                .sink { [weak self] catalogItems in
                    guard let self = self else { return }
                    
                    // Update preset donations with catalog item IDs
                    self.updatePresetDonationsFromCatalog(catalogItems)
                }
                .store(in: &cancellables)
        } else {
            isSyncingWithCatalog = false
        }
    }
    
    /// Update the DonationViewModel with the current preset amounts
    func updateDonationViewModel(_ donationViewModel: DonationViewModel) {
        var numericAmounts: [Double] = []
        for donation in presetDonations {
            if let amount = Double(donation.amount) {
                numericAmounts.append(amount)
            }
        }
        
        if !numericAmounts.isEmpty {
            donationViewModel.presetAmounts = numericAmounts
        }
    }
    
    /// Load preset donations from Square catalog
    func loadPresetDonationsFromCatalog() {
        guard let catalogService = catalogService else {
            lastSyncError = "Catalog service not connected"
            return
        }
        
        isSyncingWithCatalog = true
        lastSyncError = nil
        
        // Load donations from catalog
        catalogService.fetchPresetDonations()
    }
    
    /// Update preset donations with catalog item IDs
    private func updatePresetDonationsFromCatalog(_ catalogItems: [DonationItem]) {
        // Skip if there are no catalog items
        if catalogItems.isEmpty {
            return
        }
        
        // Create a map of amount to catalog item for easier lookup
        var catalogItemMap: [Double: DonationItem] = [:]
        for item in catalogItems {
            catalogItemMap[item.amount] = item
        }
        
        // Update local preset donations with catalog item IDs
        var updatedDonations: [PresetDonation] = []
        
        for donation in presetDonations {
            if let amount = Double(donation.amount),
               let catalogItem = catalogItemMap[amount] {
                // Update with catalog info
                updatedDonations.append(PresetDonation(
                    id: donation.id,
                    amount: donation.amount,
                    catalogItemId: catalogItem.id,
                    isSync: true
                ))
            } else {
                // Keep original but mark as not synced
                updatedDonations.append(PresetDonation(
                    id: donation.id,
                    amount: donation.amount,
                    catalogItemId: donation.catalogItemId,
                    isSync: false
                ))
            }
        }
        
        // Update the published property
        presetDonations = updatedDonations
        
        // Save the updated state
        saveToUserDefaults()
    }
    
    /// Add a new preset donation amount
    func addPresetDonation(amount: String) {
        let newDonation = PresetDonation(
            id: UUID().uuidString,
            amount: amount,
            catalogItemId: nil,
            isSync: false
        )
        
        presetDonations.append(newDonation)
        
        // Sort by amount
        sortPresetDonations()
        
        // Save settings
        saveToUserDefaults()
    }
    
    /// Remove a preset donation amount
    func removePresetDonation(at index: Int) {
        // Check if donation has a catalog item ID
        let donation = presetDonations[index]
        
        if let catalogItemId = donation.catalogItemId, let catalogService = catalogService {
            // Delete from catalog if synced
            catalogService.deletePresetDonation(id: catalogItemId)
        }
        
        // Remove from local list
        presetDonations.remove(at: index)
        
        // Save settings
        saveToUserDefaults()
    }
    
    /// Update a preset donation amount
    func updatePresetDonation(at index: Int, amount: String) {
        let donation = presetDonations[index]
        
        // Create updated donation
        let updatedDonation = PresetDonation(
            id: donation.id,
            amount: amount,
            catalogItemId: donation.catalogItemId,
            isSync: false // Mark as not synced since amount changed
        )
        
        // Replace in array
        presetDonations[index] = updatedDonation
        
        // Sort by amount
        sortPresetDonations()
        
        // Save settings
        saveToUserDefaults()
    }
    
    /// Sort preset donations by amount
    private func sortPresetDonations() {
        presetDonations.sort {
            guard let amount1 = Double($0.amount),
                  let amount2 = Double($1.amount) else {
                return false
            }
            return amount1 < amount2
        }
    }
    
    /// Create an order for a donation
    func createDonationOrder(amount: Double, isCustomAmount: Bool, completion: @escaping (String?, Error?) -> Void) {
        guard let catalogService = catalogService else {
            completion(nil, NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "Catalog service not connected"]))
            return
        }
        
        // If using a preset amount, find the matching catalog item ID
        var catalogItemId: String? = nil
        
        if !isCustomAmount {
            // Find the preset donation with the matching amount
            if let donation = presetDonations.first(where: { Double($0.amount) == amount }) {
                catalogItemId = donation.catalogItemId
            }
        }
        
        // Create the order
        catalogService.createDonationOrder(
            amount: amount,
            isCustom: isCustomAmount,
            catalogItemId: catalogItemId,
            completion: completion
        )
    }
}
