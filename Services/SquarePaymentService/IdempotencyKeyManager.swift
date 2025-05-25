//
//  IdempotencyKeyManager.swift
//  CharityPadWSquare
//
//  Created by Wilkes Shluchim on 5/18/25.
//

import Foundation
import SquareMobilePaymentsSDK

/// Manages idempotency keys for payments to prevent duplicate charges
class IdempotencyKeyManager {
    // MARK: - Private Properties
    
    private let userDefaultsKey = "IdempotencyKeys"
    private var storage: [String: String] = [:]
    
    // MARK: - Initialization
    
    init() {
        loadFromUserDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Get an existing key for a transaction or create a new one
    func getKey(for transactionId: String) -> String {
        if let existingKey = storage[transactionId] {
            return existingKey
        }
        
        let newKey = UUID().uuidString
        storage[transactionId] = newKey
        saveToUserDefaults()
        return newKey
    }
    
    /// Remove a key for a transaction
    func removeKey(for transactionId: String) {
        storage.removeValue(forKey: transactionId)
        saveToUserDefaults()
    }
    
    /// Clear all stored keys
    func clearAllKeys() {
        storage.removeAll()
        saveToUserDefaults()
    }
    
    // MARK: - Private Methods
    
    /// Load stored keys from UserDefaults
    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            storage = stored
        }
    }
    
    /// Save keys to UserDefaults
    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
