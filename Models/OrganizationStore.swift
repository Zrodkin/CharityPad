import Foundation
import Combine
import SwiftUI

class OrganizationStore: ObservableObject {
    @Published var name: String = "Your Organization"
    @Published var taxId: String = "12-3456789"
    
    init() {
        loadFromUserDefaults()
    }
    
    func loadFromUserDefaults() {
        if let name = UserDefaults.standard.string(forKey: "organizationName") {
            self.name = name
        }
        
        if let taxId = UserDefaults.standard.string(forKey: "organizationTaxId") {
            self.taxId = taxId
        }
    }
    
    func saveToUserDefaults() {
        UserDefaults.standard.set(name, forKey: "organizationName")
        UserDefaults.standard.set(taxId, forKey: "organizationTaxId")
    }
}
