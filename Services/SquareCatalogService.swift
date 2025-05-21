//
//  SquareCatalogService.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/21/25.
//
import Foundation
import Combine

/// Structure to represent a donation catalog item
struct DonationItem: Identifiable, Codable {
    var id: String
    var parentId: String
    var name: String
    var amount: Double
    var formattedAmount: String
    var type: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case parentId = "parent_id"
        case name
        case amount
        case formattedAmount = "formatted_amount"
        case type
    }
}

/// Service responsible for managing donation catalog items in Square
class SquareCatalogService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var presetDonations: [DonationItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var parentItemId: String? = nil
    
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
        
        let urlString = "\(SquareConfig.backendBaseURL)\(SquareConfig.statusEndpoint)?organization_id=\(authService.organizationId)"
        
        guard let url = URL(string: "\(SquareConfig.backendBaseURL)/api/square/catalog/list?organization_id=\(authService.organizationId)") else {
            error = "Invalid request URL"
            isLoading = false
            return
        }
        
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
                }
            }, receiveValue: { [weak self] response in
                guard let self = self else { return }
                
                // Store parent item ID if available
                if let firstItem = response.donationItems.first {
                    self.parentItemId = firstItem.parentId
                }
                
                // Sort by amount
                self.presetDonations = response.donationItems.sorted { $0.amount < $1.amount }
                print("Fetched \(self.presetDonations.count) donation preset amounts")
            })
            .store(in: &cancellables)
    }
    
    /// Save preset donation amounts to Square catalog
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
        
        // Create request body
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "amounts": amounts,
            "parent_item_id": parentItemId as Any
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
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let parentId = json["parent_id"] as? String {
                            self.parentItemId = parentId
                            print("Updated parent item ID: \(parentId)")
                        }
                        
                        if let error = json["error"] as? String {
                            self.error = error
                        } else {
                            self.error = nil
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
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
        
        // Create request body
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
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                self.isLoading = false
                
                switch completion {
                case .finished:
                    // Remove the item from the local list
                    self.presetDonations.removeAll { $0.id == id }
                case .failure(let error):
                    self.error = "Failed to delete preset donation: \(error.localizedDescription)"
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.error = error
                        } else {
                            self.error = nil
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                }
            })
            .store(in: &cancellables)
    }
    
    /// Create a donation order with line items
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
        
        // Create line item for donation
        var lineItem: [String: Any]
        
        if isCustom || catalogItemId == nil {
            // For custom amounts, use ad-hoc line item
            lineItem = [
                "name": "Custom Donation",
                "quantity": "1",
                "base_price_money": [
                    "amount": Int(amount * 100), // Convert to cents
                    "currency": "USD"
                ]
            ]
        } else {
            // For preset amounts, use catalog reference
            lineItem = [
                "catalog_object_id": catalogItemId!,
                "quantity": "1"
            ]
        }
        
        // Create request body
        let requestBody: [String: Any] = [
            "organization_id": authService.organizationId,
            "line_items": [lineItem],
            "note": "Donation via CharityPad"
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
                }
            }, receiveValue: { [weak self] data in
                guard let self = self else { return }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = json["error"] as? String {
                            self.error = error
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: error]))
                        } else if let orderId = json["order_id"] as? String {
                            // Successfully created order
                            self.error = nil
                            completion(orderId, nil)
                        } else {
                            self.error = "Unable to parse order ID from response"
                            completion(nil, NSError(domain: "com.charitypad", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse order ID from response"]))
                        }
                    }
                } catch {
                    self.error = "Failed to parse response: \(error.localizedDescription)"
                    completion(nil, error)
                }
            })
            .store(in: &cancellables)
    }
}

// MARK: - Response Types

struct CatalogResponse: Codable {
    let donationItems: [DonationItem]
    let rawItems: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case donationItems = "donation_items"
        case rawItems = "raw_items"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        donationItems = try container.decode([DonationItem].self, forKey: .donationItems)
        
        // Handle raw_items as an optional dictionary
        if let rawItemsData = try? container.decodeIfPresent(Data.self, forKey: .rawItems) {
            rawItems = try JSONSerialization.jsonObject(with: rawItemsData) as? [String: Any]
        } else {
            rawItems = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(donationItems, forKey: .donationItems)
        
        if let rawItems = rawItems {
            let jsonData = try JSONSerialization.data(withJSONObject: rawItems)
            try container.encode(jsonData, forKey: .rawItems)
        }
    }
}
