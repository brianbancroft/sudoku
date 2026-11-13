import Foundation

struct EntitlementRecord: Codable, Equatable, Sendable {
    var originalTransactionID: String
    var transactionID: String
    var productID: String
    var deviceIDs: [String]
}

/// Records which signed transactions have been presented, and which devices asked.
public final class EntitlementLedger: @unchecked Sendable {
    private var records: [String: EntitlementRecord] = [:]
    private let fileURL: URL?
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([EntitlementRecord].self, from: data) {
            for record in decoded {
                records[record.originalTransactionID] = record
            }
        }
    }

    func grant(_ claims: TransactionClaims, deviceID: String) {
        lock.lock()
        defer { lock.unlock() }
        let trimmedDevice = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existing = records[claims.originalTransactionID] {
            if !trimmedDevice.isEmpty, !existing.deviceIDs.contains(trimmedDevice) {
                existing.deviceIDs.append(trimmedDevice)
            }
            existing.transactionID = claims.transactionID
            records[claims.originalTransactionID] = existing
        } else {
            records[claims.originalTransactionID] = EntitlementRecord(
                originalTransactionID: claims.originalTransactionID,
                transactionID: claims.transactionID,
                productID: claims.productID,
                deviceIDs: trimmedDevice.isEmpty ? [] : [trimmedDevice]
            )
        }
        persistLocked()
    }

    func productIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(Set(records.values.map(\.productID))).sorted()
    }

    func devices(for productID: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return records.values.filter { $0.productID == productID }.flatMap(\.deviceIDs)
    }

    private func persistLocked() {
        guard let fileURL else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Array(records.values)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
