import Foundation

public enum VerificationMode: String, Equatable, Sendable {
    case dev
    case production

    /// Local runs default to dev so Xcode StoreKit configuration purchases work.
    /// Production refuses those transactions until Apple verification is configured.
    public static var current: VerificationMode {
        let raw = ProcessInfo.processInfo.environment["SUDOKU_IAP_MODE"]?.lowercased()
        return raw == "production" ? .production : .dev
    }
}

struct TransactionClaims: Equatable, Sendable {
    var transactionID: String
    var originalTransactionID: String
    var bundleID: String
    var productID: String
    var environment: String
    var ownership: String?
    var productType: String?
    var revoked: Bool
}

enum VerificationError: Error, Equatable {
    case malformed
    case wrongBundle
    case unknownProduct
    case revoked
    case notPurchased
    case wrongType
    case wrongEnvironment
    case xcodeNotAllowed
    case productionNotConfigured
}

enum TransactionVerifier {
    static let productionSetupMessage = """
    Production verification is not configured. Keep SUDOKU_IAP_MODE=dev only on this computer. \
    For real sales, set SUDOKU_IAP_MODE=production and verify each JWS with Apple's App Store Server API \
    (Get Transaction Info) using an issuer id, a key id, and a .p8 downloaded from App Store Connect. \
    Those values stay outside the repo. Alternatively, check the JWS x5c chain against Apple Root CA - G3. \
    This server does not accept Production or Sandbox transactions until that check is in place.
    """

    static func verify(
        jws: String,
        mode: VerificationMode,
        bundleID: String,
        knownProducts: Set<String>
    ) throws -> TransactionClaims {
        let claims = try decodeClaims(jws)
        try validateCommon(claims, bundleID: bundleID, knownProducts: knownProducts)
        switch mode {
        case .dev:
            guard claims.environment == "Xcode" else { throw VerificationError.wrongEnvironment }
        case .production:
            if claims.environment == "Xcode" {
                throw VerificationError.xcodeNotAllowed
            }
            guard claims.environment == "Production" || claims.environment == "Sandbox" else {
                throw VerificationError.wrongEnvironment
            }
            // Fail closed. No Apple key, root, or issuer id is stored in this repo.
            throw VerificationError.productionNotConfigured
        }
        return claims
    }

    static func decodeClaims(_ jws: String) throws -> TransactionClaims {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
            throw VerificationError.malformed
        }
        guard let headerData = Base64URL.decode(String(parts[0])),
              let payloadData = Base64URL.decode(String(parts[1])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            throw VerificationError.malformed
        }
        guard (header["alg"] as? String) == "ES256" else {
            throw VerificationError.malformed
        }
        guard let transactionID = payload["transactionId"] as? String, !transactionID.isEmpty,
              let bundleID = payload["bundleId"] as? String, !bundleID.isEmpty,
              let productID = payload["productId"] as? String, !productID.isEmpty,
              let environment = payload["environment"] as? String, !environment.isEmpty
        else {
            throw VerificationError.malformed
        }
        let original = (payload["originalTransactionId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? transactionID
        return TransactionClaims(
            transactionID: transactionID,
            originalTransactionID: original,
            bundleID: bundleID,
            productID: productID,
            environment: environment,
            ownership: payload["inAppOwnershipType"] as? String,
            productType: payload["type"] as? String,
            revoked: payload["revocationDate"] != nil
        )
    }

    private static func validateCommon(
        _ claims: TransactionClaims,
        bundleID: String,
        knownProducts: Set<String>
    ) throws {
        guard claims.bundleID == bundleID else { throw VerificationError.wrongBundle }
        guard knownProducts.contains(claims.productID) else { throw VerificationError.unknownProduct }
        if claims.revoked { throw VerificationError.revoked }
        if let ownership = claims.ownership, ownership != "PURCHASED", ownership != "FAMILY_SHARED" {
            throw VerificationError.notPurchased
        }
        if let productType = claims.productType, productType != "Non-Consumable" {
            throw VerificationError.wrongType
        }
    }
}

enum Base64URL {
    static func decode(_ string: String) -> Data? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: padded)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
