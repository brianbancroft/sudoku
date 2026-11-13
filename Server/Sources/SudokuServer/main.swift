import Foundation
import SudokuServerCore

let port = UInt16(ProcessInfo.processInfo.environment["PORT"] ?? "") ?? 8787
let mode = VerificationMode.current
let ledgerURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ENTITLEMENTS_PATH"] ?? "Server/data/entitlements.json")
let app = ServerApp(mode: mode, ledger: EntitlementLedger(fileURL: ledgerURL))
SocketServer.serve(port: port, app: app)
