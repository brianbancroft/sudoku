import Foundation

struct HTTPRequest: Equatable {
    var method: String
    var path: String
    var body: Data
}

struct HTTPResponse {
    var status: Int
    var body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data)
    }

    static func error(_ code: String, status: Int) -> HTTPResponse {
        json(APIError(error: code), status: status)
    }

    func wireData() -> Data {
        var header = "HTTP/1.1 \(status) \(HTTPResponse.reason(status))\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        default: "Error"
        }
    }
}

struct APIError: Codable {
    var error: String
}

struct CatalogResponse: Codable {
    var packs: [PackSummary]
}

struct HealthResponse: Codable {
    var ok: Bool
    var mode: String
    var bundleID: String
}

struct EntitlementRequest: Codable {
    var deviceID: String
    var signedTransactions: [String]
}

struct EntitlementResponse: Codable {
    var productIDs: [String]
    var packIDs: [String]
}

struct DownloadRequest: Codable {
    var deviceID: String
    var packID: String
    var signedTransaction: String
}

struct DownloadResponse: Codable {
    var packID: String
    var puzzles: [StoredPuzzle]
}

/// The four routes the app calls. Tests use this type directly, without opening a socket.
public final class ServerApp: @unchecked Sendable {
    let mode: VerificationMode
    let library: PackLibrary
    let ledger: EntitlementLedger

    public init(mode: VerificationMode = .dev, ledger: EntitlementLedger = EntitlementLedger()) {
        self.mode = mode
        self.library = PackLibrary()
        self.ledger = ledger
    }

    func response(for request: HTTPRequest) -> HTTPResponse {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        switch (request.method.uppercased(), path) {
        case ("GET", "/health"):
            return .json(HealthResponse(ok: true, mode: mode.rawValue, bundleID: PackCatalog.bundleID))
        case ("GET", "/catalog"):
            return .json(CatalogResponse(packs: PackCatalog.summaries))
        case ("POST", "/entitlements"):
            return entitlements(request.body)
        case ("POST", "/packs/download"):
            return download(request.body)
        default:
            return .error("not_found", status: 404)
        }
    }

    private func entitlements(_ body: Data) -> HTTPResponse {
        guard let payload = try? JSONDecoder().decode(EntitlementRequest.self, from: body) else {
            return .error("malformed_body", status: 400)
        }
        if payload.signedTransactions.isEmpty {
            return .json(EntitlementResponse(productIDs: ledger.productIDs(), packIDs: packIDs(for: ledger.productIDs())))
        }
        var granted = false
        for token in payload.signedTransactions {
            do {
                let claims = try verify(token)
                ledger.grant(claims, deviceID: payload.deviceID)
                granted = true
            } catch let error as VerificationError {
                if payload.signedTransactions.count == 1 {
                    return verificationFailure(error)
                }
            } catch {
                return .error("malformed", status: 400)
            }
        }
        let products = ledger.productIDs()
        if !granted && !payload.signedTransactions.isEmpty && products.isEmpty {
            return .error("not_entitled", status: 403)
        }
        return .json(EntitlementResponse(productIDs: products, packIDs: packIDs(for: products)))
    }

    private func download(_ body: Data) -> HTTPResponse {
        guard let payload = try? JSONDecoder().decode(DownloadRequest.self, from: body) else {
            return .error("malformed_body", status: 400)
        }
        guard let pack = PackCatalog.pack(id: payload.packID) else {
            return .error("unknown_pack", status: 404)
        }
        let claims: TransactionClaims
        do {
            claims = try verify(payload.signedTransaction)
        } catch let error as VerificationError {
            return verificationFailure(error)
        } catch {
            return .error("malformed", status: 400)
        }
        guard claims.productID == pack.productID else {
            return .error("wrong_product", status: 403)
        }
        guard let contents = library.contents(id: pack.id) else {
            return .error("unknown_pack", status: 404)
        }
        ledger.grant(claims, deviceID: payload.deviceID)
        return .json(DownloadResponse(packID: contents.id, puzzles: contents.puzzles))
    }

    private func verify(_ jws: String) throws -> TransactionClaims {
        try TransactionVerifier.verify(
            jws: jws,
            mode: mode,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )
    }

    private func packIDs(for productIDs: [String]) -> [String] {
        productIDs.compactMap { PackCatalog.pack(productID: $0)?.id }.sorted()
    }

    private func verificationFailure(_ error: VerificationError) -> HTTPResponse {
        switch error {
        case .malformed:
            return .error("malformed", status: 400)
        case .wrongBundle:
            return .error("wrong_bundle", status: 403)
        case .unknownProduct:
            return .error("unknown_product", status: 403)
        case .revoked:
            return .error("revoked", status: 403)
        case .notPurchased:
            return .error("not_purchased", status: 403)
        case .wrongType:
            return .error("wrong_type", status: 403)
        case .wrongEnvironment:
            return .error("wrong_environment", status: 403)
        case .xcodeNotAllowed:
            return .error("xcode_not_allowed", status: 403)
        case .productionNotConfigured:
            return .error("production_not_configured", status: 503)
        }
    }
}

enum HTTPParser {
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: data.subdata(in: 0..<separator.lowerBound), encoding: .utf8) else {
            return nil
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let bits = requestLine.split(separator: " ")
        guard bits.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.count == 2, pieces[0].lowercased() == "content-length" {
                length = Int(pieces[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = separator.upperBound
        guard data.count >= bodyStart + length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return HTTPRequest(method: String(bits[0]), path: String(bits[1]), body: body)
    }
}
