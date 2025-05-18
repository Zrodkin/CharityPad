import Foundation
import Combine
import SwiftUI

class KioskStore: ObservableObject {
    @Published var headline: String = "Tap to Donate"
    @Published var subtext: String = "Support our mission with your generous donation"
    @Published var backgroundImage: UIImage?
    @Published var logoImage: UIImage?
    @Published var presetAmounts: [String] = ["18", "36", "54", "72", "108", "180"]
    @Published var allowCustomAmount: Bool = true
    @Published var minAmount: String = "1"
    @Published var maxAmount: String = "100000"
    @Published var timeoutDuration: String = "60"
    @Published var homePageEnabled: Bool = true
    
    init() {
        loadFromUserDefaults()
    }
    
    func loadFromUserDefaults() {
        if let headline = UserDefaults.standard.string(forKey: "kioskHeadline") {
            self.headline = headline
        }
        
        if let subtext = UserDefaults.standard.string(forKey: "kioskSubtext") {
            self.subtext = subtext
        }
        
        if let presetAmountsData = UserDefaults.standard.array(forKey: "kioskPresetAmounts") as? [String] {
            self.presetAmounts = presetAmountsData
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
    }
    
    func saveToUserDefaults() {
        UserDefaults.standard.set(headline, forKey: "kioskHeadline")
        UserDefaults.standard.set(subtext, forKey: "kioskSubtext")
        UserDefaults.standard.set(presetAmounts, forKey: "kioskPresetAmounts")
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
        
        if let backgroundImage = backgroundImage, let backgroundData = backgroundImage.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(backgroundData, forKey: "kioskBackgroundImage")
        }
    }
    
    func saveSettings() {
        saveToUserDefaults()
        
        // In a real app, you might want to sync with a server here
        NotificationCenter.default.post(name: Notification.Name("KioskSettingsUpdated"), object: nil)
    }
    
    // Update the DonationViewModel with the current preset amounts
    func updateDonationViewModel(_ donationViewModel: DonationViewModel) {
        var numericAmounts: [Double] = []
        for amountString in presetAmounts {
            if let amount = Double(amountString) {
                numericAmounts.append(amount)
            }
        }
        
        if !numericAmounts.isEmpty {
            donationViewModel.presetAmounts = numericAmounts
        }
    }
}
