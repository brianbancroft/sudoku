import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PackStore {
    private(set) var listings: [PackListing] = PackProduct.fallback
    private(set) var products: [String: Product] = [:]
    private(set) var ownedProductIDs: Set<String> = []
    private(set) var downloaded: [String: DownloadedPack] = [:]
    private(set) var completed: Set<String> = []
    private(set) var isBusy = false
    private(set) var serverUnreachable = false
    var notice: String?
    var serverURL: String = ServerBaseURL.fallback

    private var updatesTask: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    func bootstrap() async {
        loadDisk()
        if updatesTask == nil {
            updatesTask = Task { await self.observeUpdates() }
        }
        await loadProducts()
        await refreshCatalog()
        await syncFromStoreKit()
    }

    func priceLabel(for productID: String) -> String? {
        products[productID]?.displayPrice
    }

    func isDownloaded(_ packID: String) -> Bool {
        downloaded[packID] != nil
    }

    func pack(id: String) -> DownloadedPack? {
        downloaded[id]
    }

    func completedCount(packID: String) -> Int {
        completed.filter { $0.hasPrefix("\(packID)/") }.count
    }

    func isComplete(packID: String, puzzleID: String) -> Bool {
        completed.contains("\(packID)/\(puzzleID)")
    }

    func markCompleted(packID: String, puzzleID: String) {
        completed.insert("\(packID)/\(puzzleID)")
        saveProgress()
    }

    func buy(_ listing: PackListing) async {
        guard let product = products[listing.productID] else {
            notice = "The App Store price isn't available yet. In the simulator, the scheme uses Products.storekit."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = Self.verified(verification) else {
                    notice = "The App Store couldn't verify that purchase."
                    return
                }
                await fulfill(transaction)
            case .userCancelled:
                break
            case .pending:
                notice = "The purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            notice = "The purchase didn't go through."
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch {
            notice = "The App Store restore didn't finish. Packs already on this phone still open."
        }
        await syncFromStoreKit()
    }

    func download(_ listing: PackListing) async {
        guard ownedProductIDs.contains(listing.productID) else { return }
        isBusy = true
        defer { isBusy = false }
        guard let transaction = await currentTransaction(for: listing.productID) else {
            notice = "StoreKit doesn't have this purchase on this phone yet. Try Restore purchases."
            return
        }
        await fulfill(transaction)
    }

    private func observeUpdates() async {
        for await update in Transaction.updates {
            if Task.isCancelled { break }
            guard let transaction = Self.verified(update) else { continue }
            await fulfill(transaction)
        }
    }

    private func syncFromStoreKit() async {
        var unfinished: [Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verified(result) else { continue }
            ownedProductIDs.insert(transaction.productID)
            unfinished.append(transaction)
        }
        for transaction in unfinished where downloaded[packID(for: transaction.productID) ?? ""] == nil {
            await fulfill(transaction)
        }
        for transaction in unfinished where downloaded[packID(for: transaction.productID) ?? ""] != nil {
            await transaction.finish()
        }
    }

    private func fulfill(_ transaction: Transaction) async {
        guard let packID = packID(for: transaction.productID) else { return }
        ownedProductIDs.insert(transaction.productID)
        do {
            try await registerAndDownload(transaction, packID: packID)
            serverUnreachable = false
            notice = nil
            await transaction.finish()
        } catch {
            serverUnreachable = true
            if downloaded[packID] != nil {
                await transaction.finish()
            } else {
                notice = "Purchased. The pack will download when the puzzle server is running."
            }
        }
    }

    private func registerAndDownload(_ transaction: Transaction, packID: String) async throws {
        let base = ServerBaseURL.normalized(serverURL) ?? ServerBaseURL.fallback
        guard let root = URL(string: base) else { throw PackClientError.unreachable }
        let deviceID = DeviceIdentity.current()
        let jws = transaction.jwsRepresentation
        let entitlementsURL = root.appendingPathComponent("entitlements")
        _ = try await post(entitlementsURL, body: EntitlementBody(deviceID: deviceID, signedTransactions: [jws]))
        let downloadURL = root.appendingPathComponent("packs").appendingPathComponent("download")
        let payload = try await post(
            downloadURL,
            body: DownloadBody(deviceID: deviceID, packID: packID, signedTransaction: jws)
        )
        let decoded = try JSONDecoder().decode(DownloadEnvelope.self, from: payload)
        let pack = DownloadedPack(id: decoded.packID, puzzles: decoded.puzzles)
        downloaded[pack.id] = pack
        try save(pack)
    }

    private func refreshCatalog() async {
        let base = ServerBaseURL.normalized(serverURL) ?? ServerBaseURL.fallback
        guard let url = URL(string: base)?.appendingPathComponent("catalog") else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                serverUnreachable = true
                return
            }
            let catalog = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
            if !catalog.packs.isEmpty {
                listings = catalog.packs
                serverUnreachable = false
            }
        } catch {
            serverUnreachable = true
        }
    }

    private func loadProducts() async {
        do {
            let found = try await Product.products(for: PackProduct.all)
            var map: [String: Product] = [:]
            for product in found {
                map[product.id] = product
            }
            products = map
        } catch {
            notice = "StoreKit couldn't load pack prices."
        }
    }

    private func currentTransaction(for productID: String) async -> Transaction? {
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verified(result), transaction.productID == productID else { continue }
            return transaction
        }
        return nil
    }

    private func packID(for productID: String) -> String? {
        listings.first { $0.productID == productID }?.id
            ?? PackProduct.fallback.first { $0.productID == productID }?.id
    }

    private static func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            return nil
        }
    }

    private func post(_ url: URL, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PackClientError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw PackClientError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw PackClientError.rejected }
        return data
    }

    private func loadDisk() {
        guard let directory = try? Self.directory() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [String: DownloadedPack] = [:]
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "progress.json" {
            guard let data = try? Data(contentsOf: file),
                  let pack = try? JSONDecoder().decode(DownloadedPack.self, from: data) else { continue }
            loaded[pack.id] = pack
        }
        downloaded = loaded
        let progressURL = directory.appendingPathComponent("progress.json")
        if let data = try? Data(contentsOf: progressURL),
           let progress = try? JSONDecoder().decode(ProgressFile.self, from: data) {
            completed = Set(progress.completed)
        }
    }

    private func save(_ pack: DownloadedPack) throws {
        let directory = try Self.directory()
        let url = directory.appendingPathComponent("\(pack.id).json")
        let data = try JSONEncoder().encode(pack)
        try data.write(to: url, options: .atomic)
    }

    private func saveProgress() {
        guard let directory = try? Self.directory() else { return }
        let url = directory.appendingPathComponent("progress.json")
        let payload = ProgressFile(completed: Array(completed).sorted())
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SudokuPacks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum PackClientError: Error {
    case unreachable
    case rejected
    case badResponse
}

private struct CatalogEnvelope: Codable {
    var packs: [PackListing]
}

private struct EntitlementBody: Codable {
    var deviceID: String
    var signedTransactions: [String]
}

private struct DownloadBody: Codable {
    var deviceID: String
    var packID: String
    var signedTransaction: String
}

private struct DownloadEnvelope: Codable {
    var packID: String
    var puzzles: [DownloadedPuzzle]
}

private struct ProgressFile: Codable {
    var completed: [String]
}
