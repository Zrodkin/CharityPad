import Foundation

/// Manages the association between business-logic specific identifiers and uniquely generated idempotency keys.
class IdempotencyKeyManager {
    typealias IdempotencyKey = String

    // MARK: - Properties

    private let userDefaultsKey = "IdempotencyKeys"

    private var storage: [String: IdempotencyKey] = [:] {
        didSet {
            saveToUserDefaults()
        }
    }

    // MARK: - Initializers

    init() {
        storage = loadFromUserDefaults() ?? [:]
    }

    // MARK: - Methods

    /// Store an idempotency key for a transaction ID
    func store(id: String, idempotencyKey: IdempotencyKey) {
        storage[id] = idempotencyKey
    }

    /// Remove an idempotency key for a transaction ID
    func removeKey(for id: String) {
        storage.removeValue(forKey: id)
    }

    /// Get an idempotency key for a transaction ID (returns nil if not found)
    func getKey(for id: String) -> IdempotencyKey? {
        return storage[id]
    }

    // MARK: - Private Methods

    private func loadFromUserDefaults() -> [String: IdempotencyKey]? {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            return try? JSONDecoder().decode([String: IdempotencyKey].self, from: data)
        }
        return nil
    }

    private func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(storage) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
