import Foundation
import Combine

/// Structure to represent a donation catalog item - UPDATED to match backend response
struct DonationItem: Identifiable, Codable {
    var id: String
    var parentId: String
    var name: String
    var amount: Double
    var formattedAmount: String
    var type: String
    var ordinal: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case parentId = "parent_id"
        case name
        case amount
        case formattedAmount = "formatted_amount"
        case type
        case ordinal
    }
}

/// Parent item information
struct ParentItem: Identifiable, Codable {
    var id: String
    var name: String
    var description: String?
    var productType: String?
    var updatedAt: String?
    var version: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case productType = "product_type"
        case updatedAt = "updated_at"
        case version
    }
}

/// Service responsible for managing donation catalog items in Square
class SquareCatalogService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var presetDonations: [DonationItem] = []
    @Published var parentItems: [ParentItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var parentItemId: String? = nil
    @Published var lastSyncTime: Date? = nil
    
    // MARK: - Private Properties
    
    private let authService: SquareAuthService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(authService: SquareAuthService) {
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    /// Fetch preset donations from Square catalog
    func fetchPresetDonations() {
        guard authService.isAuthenticated else {
            error = "Not connected to Square"
            return
        }
        
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/catalog/list?organization_id=\(authService.organizationId)") else {
            error = "Invalid request URL"
            isLoading = false
            return
        }
        
        print("📋 Fetching catalog items from: \(url)")
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: CatalogResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    self.error = "Failed to fetch donation items: \(error.localizedDescription)"
                    print("❌ Catalog fetch error: \(error)")
                }
            }, receiveValue: { [weak self] response in
                guard let self = self else { return }
                
                // Store parent items and donation items
                self.parentItems = response.parentItems
                self.presetDonations = response.donationItems.sorted { $0.amount < $1.amount }
                
                // Store parent item ID if available
                if let firstParent = response.parentItems.first {
                    self.parentItemId = firstParent.id
                }
                
                // Update last sync time
                self.lastSyncTime = Date()
                
                print("✅ Fetched \(self.presetDonations.count) donation items with \(self.parentItems.count) parent items")
                print("📊 Amounts: \(self.presetDonations.map { $0.amount })")
            })
            .store(in: &cancellables)
    }
    
    /// Save preset donation amounts to Square catalog using batch upsert
    func savePresetDonations(amounts: [Double]) {
        guard authService.isAuthenticated else {
            error = "Not connected to Square"
            return
        }
        
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/catalog/batch-upsert") else {
            error = "Invalid request URL"
            isLoading = false
            return
        }
        
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "amounts": amounts,
            "parent_item_id": parentItemId as Any,
            "parent_item_name": "Donations",
            "parent_item_description": "Donation preset amounts"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            self.error = "Failed to serialize request: \(error.localizedDescription)"
            isLoading = false
            return
        }
        
        print("💾 Saving \(amounts.count) preset amounts: \(amounts)")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                switch completion {
                case .finished:
                    // Refresh the list after saving
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.fetchPresetDonations()
                    }
                case .failure(let error):
                    self.error = "Failed to save preset donations: \(error.localizedDescription)"
                    self.isLoading = false
                    print("❌ Save error: \(error)")
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let parentId = json["parent_item_id"] as? String {
                            self.parentItemId = parentId
                            print("✅ Updated parent item ID: \(parentId)")
                        }
                        
                        if let error = json["error"] as? String {
                            self.error = error
                            print("❌ Backend error: \(error)")
                        } else {
                            self.error = nil
                            self.lastSyncTime = Date()
                            print("✅ Successfully saved \(amounts.count) preset donations")
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                    print("❌ Parse error: \(error)")
                }
            })
            .store(in: &cancellables)
    }
    
    /// Delete a preset donation from the catalog
    func deletePresetDonation(id: String) {
        guard authService.isAuthenticated else {
            error = "Not connected to Square"
            return
        }
        
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/catalog/delete") else {
            error = "Invalid request URL"
            isLoading = false
            return
        }
        
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "object_id": id
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            self.error = "Failed to serialize request: \(error.localizedDescription)"
            isLoading = false
            return
        }
        
        print("🗑️ Deleting preset donation: \(id)")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                switch completion {
                case .finished:
                    self.presetDonations.removeAll { $0.id == id }
                    print("✅ Successfully deleted preset donation")
                case .failure(let error):
                    self.error = "Failed to delete preset donation: \(error.localizedDescription)"
                    print("❌ Delete error: \(error)")
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.error = error
                            print("❌ Delete backend error: \(error)")
                        } else {
                            self.error = nil
                            print("✅ Delete successful")
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                    print("❌ Delete parse error: \(error)")
                }
            })
            .store(in: &cancellables)
    }
    
    /// Create a donation order with line items (for order-based payment flow)
    func createDonationOrder(amount: Double, isCustom: Bool = false, catalogItemId: String? = nil, completion: @escaping (String?, Error?) -> Void) {
        guard authService.isAuthenticated else {
            error = "Not connected to Square"
            completion(nil, NSError(domain: "com.charitypad", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not connected to Square"]))
            return
        }
        
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/orders/create") else {
            error = "Invalid request URL"
            isLoading = false
            completion(nil, NSError(domain: "com.charitypad", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid request URL"]))
            return
        }
        
        var lineItem: [String: Any]
        
        if isCustom || catalogItemId == nil {
            lineItem = [
                "name": "Custom Donation",
                "quantity": "1",
                "base_price_money": [
                    "amount": Int(amount * 100),
                    "currency": "USD"
                ]
            ]
            print("📝 Creating ad-hoc line item for custom amount: $\(amount)")
        } else {
            lineItem = [
                "catalog_object_id": catalogItemId!,
                "quantity": "1"
            ]
            print("📝 Creating catalog line item for preset amount: $\(amount) (ID: \(catalogItemId!))")
        }
        
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "line_items": [lineItem],
            "reference_id": "donation_\(Int(Date().timeIntervalSince1970))",
            "state": "OPEN"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            self.error = "Failed to serialize request: \(error.localizedDescription)"
            isLoading = false
            completion(nil, error)
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completionResult in
                guard let self = self else { return }
                self.isLoading = false
                
                switch completionResult {
                case .finished:
                    break
                case .failure(let error):
                    self.error = "Failed to create order: \(error.localizedDescription)"
                    completion(nil, error)
                    print("❌ Order creation error: \(error)")
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.error = error
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: error]))
                            print("❌ Order creation backend error: \(error)")
                        } else if let orderId = json["order_id"] as? String {
                            self.error = nil
                            completion(orderId, nil)
                            print("✅ Order created successfully: \(orderId)")
                        } else {
                            self.error = "Unable to parse order ID from response"
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse order ID from response"]))
                            print("❌ No order ID in response")
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                    completion(nil, error)
                    print("❌ Order response parse error: \(error)")
                }
            })
            .store(in: &cancellables)
    }
    
    /// Find catalog item ID for a specific amount
    func catalogItemId(for amount: Double) -> String? {
        return presetDonations.first { $0.amount == amount }?.id
    }
}

// MARK: - Response Types

struct CatalogResponse: Codable {
    let donationItems: [DonationItem]
    let parentItems: [ParentItem]
    let pagination: PaginationInfo?
    let metadata: MetadataInfo?
    
    enum CodingKeys: String, CodingKey {
        case donationItems = "donation_items"
        case parentItems = "parent_items"
        case pagination
        case metadata
    }
}

struct PaginationInfo: Codable {
    let cursor: String?
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case cursor
        case hasMore = "has_more"
    }
}

struct MetadataInfo: Codable {
    let totalVariations: Int
    let totalParentItems: Int
    let searchStrategy: String
    
    enum CodingKeys: String, CodingKey {
        case totalVariations = "total_variations"
        case totalParentItems = "total_parent_items"
        case searchStrategy = "search_strategy"
    }
}
