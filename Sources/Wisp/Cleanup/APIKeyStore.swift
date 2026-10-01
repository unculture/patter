import Foundation
import Security

/// Keeps the OpenRouter API key in the login keychain, and a copy in memory while Wisp runs.
@MainActor
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()

    @Published private(set) var key: String?

    private let service = "com.unculture.Wisp"
    private let account = "OpenRouter API key"

    private init() {
        key = Self.read(service: service, account: account)
    }

    var hasKey: Bool { key != nil }

    /// The last four characters, to show which key is saved.
    var maskedKey: String {
        guard let key else { return "" }
        return "••••" + key.suffix(4)
    }

    @discardableResult
    func save(_ newKey: String) -> Bool {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Wisp OpenRouter API key",
            kSecValueData as String: Data(trimmed.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            NSLog("Wisp: could not save the API key in the keychain (\(status))")
            return false
        }
        key = trimmed
        return true
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        key = nil
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
