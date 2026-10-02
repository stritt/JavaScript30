import Foundation
import Security

/// Storage for the session JWT.
protocol TokenStore: AnyObject {
    var token: String? { get set }
}

/// Keychain-backed token store (generic password, this device only).
final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "app.stepquest.ios.session", account: String = "sessionToken") {
        self.service = service
        self.account = account
    }

    var token: String? {
        get { read() }
        set {
            if let newValue { write(newValue) } else { delete() }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory store for tests and previews.
final class InMemoryTokenStore: TokenStore {
    var token: String?
    init(token: String? = nil) { self.token = token }
}
