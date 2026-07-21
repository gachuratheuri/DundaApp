import Foundation
import CryptoKit
import Security

/// iOS Keychain-backed Curve25519 signing material for protocol-v2 credentials.
/// The private key is never serialised into JavaScript or AsyncStorage.
final class DeviceKeyStore {
    private let tag: String
    init(tag: String = "dunda.ticket.device.v2") { self.tag = tag }

    func publicKey() throws -> Data { try loadOrCreate().publicKey.rawRepresentation }
    func sign(_ payload: Data) throws -> Data { try loadOrCreate().signature(for: payload) }

    private func loadOrCreate() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag.data(using: .utf8)!, kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        let add: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag.data(using: .utf8)!, kSecValueData as String: key.rawRepresentation, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw NSError(domain: "DundaDeviceKey", code: 1) }
        return key
    }
}
