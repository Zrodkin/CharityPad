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
        
        // ✅ FIXED: Added missing catalog sync connection
        service.$presetDonations
            .sink { [weak self] catalogItems in
                self?.updatePresetDonationsFromCatalog(catalogItems)
            }
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
        
        // If catalog service is connected and authenticated, sync preset amounts
        if let catalogService = catalogService {
            syncPresetAmountsWithCatalog(using: catalogService)
        }
        
        // Post notification that settings were updated
        NotificationCenter.default.post(name: Notification.Name("KioskSettingsUpdated"), object: nil)
        
        print("💾 Kiosk settings saved")
    }

    /// Sync preset donation amounts with Square catalog
    func syncPresetAmountsWithCatalog(using service: SquareCatalogService) {
        print("🔄 Starting catalog sync with \(presetDonations.count) preset donations")
        
        isSyncingWithCatalog = true
        lastSyncError = nil
        
        // Extract amounts as doubles, filtering out invalid amounts
        let amountValues = presetDonations.compactMap { donation -> Double? in
            guard let amount = Double(donation.amount), amount > 0 else {
                print("⚠️ Skipping invalid amount: \(donation.amount)")
                return nil
            }
            return amount
        }
        
        // Only sync if we have valid amounts
        if !amountValues.isEmpty {
            print("📤 Syncing amounts: \(amountValues)")
            service.savePresetDonations(amounts: amountValues)
            
            // Update sync status
            lastSyncTime = Date()
            saveToUserDefaults()
        } else {
            print("❌ No valid amounts to sync")
            isSyncingWithCatalog = false
            lastSyncError = "No valid amounts to sync"
        }
    }

    /// Load preset donations from Square catalog
    func loadPresetDonationsFromCatalog() {
        guard let catalogService = catalogService else {
            lastSyncError = "Catalog service not connected"
            print("❌ Cannot load from catalog: service not connected")
            return
        }
        
        print("📥 Loading preset donations from catalog")
        isSyncingWithCatalog = true
        lastSyncError = nil
        
        // Fetch donations from catalog
        catalogService.fetchPresetDonations()
    }

    /// Create an order for a donation using catalog integration
    func createDonationOrder(amount: Double, isCustomAmount: Bool, completion: @escaping (String?, Error?) -> Void) {
        guard let catalogService = catalogService else {
            let error = NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "Catalog service not connected"])
            completion(nil, error)
            return
        }
        
        // If using a preset amount, find the matching catalog item ID
        var catalogItemId: String? = nil
        
        if !isCustomAmount {
            // Find the preset donation with the matching amount
            if let donation = presetDonations.first(where: { Double($0.amount) == amount }) {
                catalogItemId = donation.catalogItemId
                print("📋 Using catalog item ID: \(catalogItemId ?? "nil") for amount: $\(amount)")
            } else {
                print("⚠️ No catalog item found for preset amount: $\(amount)")
            }
        }
        
        // Create the order using the catalog service
        catalogService.createDonationOrder(
            amount: amount,
            isCustom: isCustomAmount,
            catalogItemId: catalogItemId,
            completion: completion
        )
    }

    /// Add a new preset donation amount
    func addPresetDonation(amount: String) {
        // Validate the amount
        guard let numericAmount = Double(amount), numericAmount > 0 else {
            print("❌ Invalid amount for new preset donation: \(amount)")
            return
        }
        
        // Check if amount already exists
        let existingAmount = presetDonations.contains { Double($0.amount) == numericAmount }
        if existingAmount {
            print("⚠️ Preset amount $\(amount) already exists")
            return
        }
        
        print("➕ Adding new preset donation: $\(amount)")
        
        let newDonation = PresetDonation(
            id: UUID().uuidString,
            amount: amount,
            catalogItemId: nil,
            isSync: false
        )
        
        presetDonations.append(newDonation)
        
        // Sort by amount
        sortPresetDonations()
        
        // Save settings (this will trigger catalog sync)
        saveSettings()
    }

    /// Remove a preset donation amount
    func removePresetDonation(at index: Int) {
        guard index >= 0 && index < presetDonations.count else {
            print("❌ Invalid index for removing preset donation: \(index)")
            return
        }
        
        let donation = presetDonations[index]
        print("🗑️ Removing preset donation: $\(donation.amount)")
        
        // If donation has a catalog item ID and is synced, we should delete from catalog
        if let catalogItemId = donation.catalogItemId,
           donation.isSync,
           let catalogService = catalogService {
            print("🗑️ Deleting from Square catalog: \(catalogItemId)")
            catalogService.deletePresetDonation(id: catalogItemId)
        }
        
        // Remove from local list
        presetDonations.remove(at: index)
        
        // Save settings
        saveSettings()
    }

    /// Update a preset donation amount
    func updatePresetDonation(at index: Int, amount: String) {
        guard index >= 0 && index < presetDonations.count else {
            print("❌ Invalid index for updating preset donation: \(index)")
            return
        }
        
        // Validate the new amount
        guard let numericAmount = Double(amount), numericAmount > 0 else {
            print("❌ Invalid amount for updating preset donation: \(amount)")
            return
        }
        
        let donation = presetDonations[index]
        print("✏️ Updating preset donation from $\(donation.amount) to $\(amount)")
        
        // Create updated donation - mark as not synced since amount changed
        let updatedDonation = PresetDonation(
            id: donation.id,
            amount: amount,
            catalogItemId: donation.catalogItemId, // Keep existing catalog ID for now
            isSync: false // Mark as not synced since amount changed
        )
        
        // Replace in array
        presetDonations[index] = updatedDonation
        
        // Sort by amount
        sortPresetDonations()
        
        // Save settings (this will trigger catalog sync)
        saveSettings()
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
    
    // ✅ FIXED: Added missing sync method
    /// Update preset donations with catalog item IDs and sync status
    private func updatePresetDonationsFromCatalog(_ catalogItems: [DonationItem]) {
        print("🔄 Updating preset donations from catalog: \(catalogItems.count) items")
        
        // Skip if there are no catalog items
        if catalogItems.isEmpty {
            print("⚠️ No catalog items to sync")
            return
        }
        
        // Create a map of amount to catalog item for easier lookup
        var catalogItemMap: [Double: DonationItem] = [:]
        for item in catalogItems {
            catalogItemMap[item.amount] = item
            print("📋 Catalog item: $\(item.amount) -> ID: \(item.id)")
        }
        
        // Update local preset donations with catalog item IDs
        var updatedDonations: [PresetDonation] = []
        var hasChanges = false
        
        for donation in presetDonations {
            guard let amount = Double(donation.amount) else {
                print("⚠️ Invalid amount in preset donation: \(donation.amount)")
                // Keep original but mark as not synced
                updatedDonations.append(PresetDonation(
                    id: donation.id,
                    amount: donation.amount,
                    catalogItemId: nil,
                    isSync: false
                ))
                continue
            }
            
            if let catalogItem = catalogItemMap[amount] {
                // Update with catalog info
                let updatedDonation = PresetDonation(
                    id: donation.id,
                    amount: donation.amount,
                    catalogItemId: catalogItem.id,
                    isSync: true
                )
                updatedDonations.append(updatedDonation)
                
                // Check if this is actually a change
                if donation.catalogItemId != catalogItem.id || donation.isSync != true {
                    hasChanges = true
                    print("✅ Synced: $\(amount) -> ID: \(catalogItem.id)")
                }
            } else {
                // Keep original but mark as not synced
                let updatedDonation = PresetDonation(
                    id: donation.id,
                    amount: donation.amount,
                    catalogItemId: donation.catalogItemId,
                    isSync: false
                )
                updatedDonations.append(updatedDonation)
                
                // Check if this is a change in sync status
                if donation.isSync != false {
                    hasChanges = true
                    print("❌ Not synced: $\(amount) (not found in catalog)")
                }
            }
        }
        
        // Also add any catalog items that don't have corresponding preset donations
        for catalogItem in catalogItems {
            let existsInPresets = updatedDonations.contains { donation in
                Double(donation.amount) == catalogItem.amount
            }
            
            if !existsInPresets {
                print("➕ Adding catalog item not in presets: $\(catalogItem.amount)")
                let newDonation = PresetDonation(
                    id: UUID().uuidString,
                    amount: String(format: "%.0f", catalogItem.amount), // Remove decimal if whole number
                    catalogItemId: catalogItem.id,
                    isSync: true
                )
                updatedDonations.append(newDonation)
                hasChanges = true
            }
        }
        
        // Sort by amount
        updatedDonations.sort {
            guard let amount1 = Double($0.amount),
                  let amount2 = Double($1.amount) else {
                return false
            }
            return amount1 < amount2
        }
        
        // Only update if there are actual changes
        if hasChanges {
            print("💾 Updating preset donations with \(updatedDonations.count) items")
            presetDonations = updatedDonations
            
            // Update sync status
            isSyncingWithCatalog = false
            lastSyncTime = Date()
            lastSyncError = nil
            
            // Save the updated state
            saveToUserDefaults()
            
            print("✅ Catalog sync completed successfully")
        } else {
            print("ℹ️ No changes detected in catalog sync")
            isSyncingWithCatalog = false
        }
    }
}
