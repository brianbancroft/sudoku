import XCTest
import SudokuEngine
@testable import SudokuServerCore

final class ServerTests: XCTestCase {
    func testCatalogListsThreePacks() {
        let response = ServerApp().response(for: HTTPRequest(method: "GET", path: "/catalog", body: Data()))
        let catalog = try! JSONDecoder().decode(CatalogResponse.self, from: response.body)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(catalog.packs.map(\.id), ["quiet-start", "hard-lines", "long-night"])
        XCTAssertEqual(catalog.packs.map(\.productID), [
            "com.brianbancroft.sudoku.pack.starter",
            "com.brianbancroft.sudoku.pack.hard",
            "com.brianbancroft.sudoku.pack.expert",
        ])
        XCTAssertEqual(catalog.packs.map(\.puzzleCount), [6, 6, 4])
    }

    func testDevModeAcceptsXcodeTransactionAndRejectsOtherEnvironments() throws {
        let xcode = try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Xcode"),
            mode: .dev,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )
        XCTAssertEqual(xcode.productID, "com.brianbancroft.sudoku.pack.starter")
        XCTAssertEqual(xcode.environment, "Xcode")

        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Production"),
            mode: .dev,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .wrongEnvironment)
        }
    }

    func testVerifierRejectsMalformedRevokedAndUnknownProducts() {
        XCTAssertThrowsError(try TransactionVerifier.decodeClaims("not-a-jws"))
        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.example.nope", environment: "Xcode"),
            mode: .dev,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .unknownProduct)
        }
        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(
                productID: "com.brianbancroft.sudoku.pack.hard",
                environment: "Xcode",
                extra: ["revocationDate": 1_700_000_000_000]
            ),
            mode: .dev,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .revoked)
        }
        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Xcode", bundleID: "com.example.other"),
            mode: .dev,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .wrongBundle)
        }
    }

    func testProductionModeFailsClosedWithoutAppleCredentials() {
        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Xcode"),
            mode: .production,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .xcodeNotAllowed)
        }
        XCTAssertThrowsError(try TransactionVerifier.verify(
            jws: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Sandbox"),
            mode: .production,
            bundleID: PackCatalog.bundleID,
            knownProducts: PackCatalog.productIDs
        )) { error in
            XCTAssertEqual(error as? VerificationError, .productionNotConfigured)
        }
        XCTAssertTrue(TransactionVerifier.productionSetupMessage.contains("App Store Server API"))
        XCTAssertFalse(TransactionVerifier.productionSetupMessage.contains("BEGIN"))
    }

    func testDownloadRequiresTheMatchingEntitlement() throws {
        let app = ServerApp()
        let denied = app.response(for: HTTPRequest(
            method: "POST",
            path: "/packs/download",
            body: try JSONEncoder().encode(DownloadRequest(
                deviceID: "phone-a",
                packID: "hard-lines",
                signedTransaction: SampleJWS.make(productID: "com.brianbancroft.sudoku.pack.starter", environment: "Xcode")
            ))
        ))
        XCTAssertEqual(denied.status, 403)

        let allowed = app.response(for: HTTPRequest(
            method: "POST",
            path: "/packs/download",
            body: try JSONEncoder().encode(DownloadRequest(
                deviceID: "phone-a",
                packID: "quiet-start",
                signedTransaction: SampleJWS.make(
                    productID: "com.brianbancroft.sudoku.pack.starter",
                    environment: "Xcode",
                    transactionID: "tx-start"
                )
            ))
        ))
        XCTAssertEqual(allowed.status, 200)
        let pack = try JSONDecoder().decode(DownloadResponse.self, from: allowed.body)
        XCTAssertEqual(pack.puzzles.count, 6)
        XCTAssertEqual(pack.puzzles.map(\.id), (1...6).map { "quiet-start-\($0)" })

        let again = app.response(for: HTTPRequest(
            method: "POST",
            path: "/entitlements",
            body: try JSONEncoder().encode(EntitlementRequest(
                deviceID: "phone-b",
                signedTransactions: [SampleJWS.make(
                    productID: "com.brianbancroft.sudoku.pack.starter",
                    environment: "Xcode",
                    transactionID: "tx-start"
                )]
            ))
        ))
        let owned = try JSONDecoder().decode(EntitlementResponse.self, from: again.body)
        XCTAssertEqual(owned.productIDs, ["com.brianbancroft.sudoku.pack.starter"])
        XCTAssertEqual(owned.packIDs, ["quiet-start"])
        XCTAssertEqual(app.ledger.devices(for: "com.brianbancroft.sudoku.pack.starter").sorted(), ["phone-a", "phone-b"])
    }

    func testPackPuzzlesHaveOneSolutionEach() {
        let library = PackLibrary()
        let packs = library.allContents()
        XCTAssertEqual(packs.count, 3)
        for pack in packs {
            let definition = PackCatalog.pack(id: pack.id)
            XCTAssertEqual(pack.puzzles.count, definition?.puzzles.count)
            for puzzle in pack.puzzles {
                XCTAssertEqual(
                    SudokuSolver.solutions(of: puzzle.givens, limit: 2),
                    [puzzle.solution],
                    puzzle.id
                )
                XCTAssertEqual(SudokuGenerator.ratedDifficulty(of: puzzle.givens), puzzle.difficulty, puzzle.id)
                for index in puzzle.givens.indices where puzzle.givens[index] != 0 {
                    XCTAssertEqual(puzzle.givens[index], puzzle.solution[index])
                }
            }
        }
    }

    func testParserHonorsContentLength() throws {
        let body = Data("{\"ok\":true}".utf8)
        var raw = Data("POST /entitlements HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        raw.append(body)
        raw.append(Data("TRAILING".utf8))
        let request = try XCTUnwrap(HTTPParser.parse(raw))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/entitlements")
        XCTAssertEqual(request.body, body)
    }
}

enum SampleJWS {
    static func make(
        productID: String,
        environment: String,
        bundleID: String = PackCatalog.bundleID,
        transactionID: String = "tx-1",
        extra: [String: Any] = [:]
    ) -> String {
        var payload: [String: Any] = [
            "transactionId": transactionID,
            "originalTransactionId": transactionID,
            "bundleId": bundleID,
            "productId": productID,
            "environment": environment,
            "type": "Non-Consumable",
            "inAppOwnershipType": "PURCHASED",
        ]
        for (key, value) in extra {
            payload[key] = value
        }
        let header = Base64URL.encode(Data(#"{"alg":"ES256","typ":"JWT"}"#.utf8))
        let body = Base64URL.encode(try! JSONSerialization.data(withJSONObject: payload))
        let signature = Base64URL.encode(Data("xcode-test-signature".utf8))
        return "\(header).\(body).\(signature)"
    }
}
