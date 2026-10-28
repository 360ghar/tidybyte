import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            String(localized: "Keychain operation failed with status \(status).", comment: "Keychain error with OSStatus code")
        case .invalidData:
            String(localized: "Keychain returned invalid data.", comment: "Keychain data decoding error")
        }
    }
}

public actor KeychainStore {
    private let service = AppIdentity.bundleIdentifier
    private let inMemory: Bool
    private var testValues: [String: String] = [:]

    public init(inMemory: Bool = false) { self.inMemory = inMemory }

    public func saveAPIKey(_ apiKey: String, account: String = "openai-compatible") throws {
        if inMemory { testValues[account] = apiKey; return }
        let data = Data(apiKey.utf8)
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Update-in-place first: delete-then-add could lose the key entirely if
        // the add failed after the delete succeeded.
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func loadAPIKey(account: String = "openai-compatible") throws -> String? {
        if inMemory { return testValues[account] }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return apiKey
    }

    public func deleteAPIKey(account: String = "openai-compatible") throws {
        if inMemory { testValues.removeValue(forKey: account); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
