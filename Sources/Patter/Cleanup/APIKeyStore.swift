import Foundation
import Security

/// Keeps the OpenRouter API key in the login keychain, and a copy in memory while Patter runs.
///
/// For an app without an Apple team ID, the keychain ties each item to the exact build: after a
/// rebuild, the first read asks the user one time. A rebuilt app also cannot delete an item that
/// an older build created, but it can overwrite the item's value. So `save` and `delete` fall
/// back to an overwrite, and an empty value means "no key".
@MainActor
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()

    @Published private(set) var key: String?

    private let service = "com.unculture.Patter"
    private let account = "OpenRouter"

    /// The snapshot command sets this to false. The keychain asks the user before it gives the key
    /// to a binary other than the installed app.
    static var readsKeychain = true

    private init() {
        guard Self.readsKeychain else { return }
        let copiedFlag = "copiedWispKeychainItem"
        if let current = Self.read(service: service, account: account) {
            key = current
        } else if !UserDefaults.standard.bool(forKey: copiedFlag),
                  let old = Self.read(service: WispMigration.bundleIdentifier, account: account) {
            // Patter was called Wisp: copy the key from the item of Wisp.
            key = old
            if Self.add(old, service: service, account: account) != errSecSuccess {
                NSLog("Patter: could not copy the API key to a new keychain item")
            }
        }
        // Look at the item of Wisp only one time: each read of it asks the user.
        UserDefaults.standard.set(true, forKey: copiedFlag)
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
        Self.remove(service: service, account: account)
        var status = Self.add(trimmed, service: service, account: account)
        if status == errSecDuplicateItem {
            // An item that this build cannot delete: replace its value instead.
            let query = Self.query(service: service, account: account)
            let changes = [kSecValueData as String: Data(trimmed.utf8)]
            status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        }
        guard status == errSecSuccess else {
            NSLog("Patter: could not save the API key in the keychain (\(status))")
            return false
        }
        key = trimmed
        return true
    }

    func delete() {
        Self.remove(service: service, account: account)
        key = nil
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func add(_ value: String, service: String, account: String) -> OSStatus {
        var attributes = query(service: service, account: account)
        attributes[kSecAttrLabel as String] = "Patter OpenRouter key"
        attributes[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func remove(service: String, account: String) {
        let query = query(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            // An item that an older build created: blank its value instead.
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data()] as CFDictionary)
        }
    }

    private static func read(service: String, account: String) -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, !data.isEmpty
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
