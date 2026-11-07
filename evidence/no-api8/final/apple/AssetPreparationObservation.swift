import Foundation
import Speech
import SaytileKit

/// Evidence wrapper around the existing official production preparation call.
/// It records counts for other reservations and never releases a locale.
enum AssetPreparationObservation {
    struct Snapshot: Codable, Sendable {
        let date: Double
        let supported: Bool
        let installed: Bool
        let inventoryStatus: String
        let reservedCount: Int
        let maximumReserved: Int
        let targetAlreadyReserved: Bool
    }
    struct Receipt: Codable, Sendable {
        var before: Snapshot
        var after: Snapshot?
        var preparationCalls = 0
        var deadlineSeconds = 180
        var outcome = "checking"
        var errorDomain: String?
        var errorCode: Int?
    }
    enum Result: Sendable { case completed, timedOut, cancelled, failed(String, Int) }

    static func snapshot() async -> Snapshot {
        let availability = await AppleSpeechService.availability()
        let reserved = await AssetInventory.reservedLocales
        let target = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN"))
        var status = "unsupported"
        if let target {
            let transcriber = SpeechTranscriber(locale: target, preset: .progressiveTranscription)
            switch await AssetInventory.status(forModules: [transcriber]) {
            case .installed: status = "installed"
            case .downloading: status = "downloading"
            case .supported: status = "supported"
            case .unsupported: status = "unsupported"
            @unknown default: status = "unknown"
            }
        }
        return Snapshot(date: Date().timeIntervalSince1970, supported: availability.supported,
            installed: availability.installed, inventoryStatus: status, reservedCount: reserved.count,
            maximumReserved: AssetInventory.maximumReservedLocales,
            targetAlreadyReserved: target.map { reserved.contains($0) } ?? false)
    }
    static func save(_ receipt: Receipt, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(receipt).write(to: url, options: .atomic)
    }
    static func prepareIfNeeded() async throws {
        guard let path = ProcessInfo.processInfo.environment["SAYTILE_ASSET_RECEIPT"] else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = URL(fileURLWithPath: path), before = await snapshot()
        var receipt = Receipt(before: before)
        try save(receipt, to: url)
        if before.installed { receipt.outcome = "already_installed" }
        else if !before.supported || before.inventoryStatus == "unsupported" { receipt.outcome = "unsupported" }
        else if !before.targetAlreadyReserved && before.reservedCount >= before.maximumReserved {
            receipt.outcome = "skipped_no_free_locale_reservation"
        } else {
            receipt.preparationCalls = 1; receipt.outcome = "preparing"; try save(receipt, to: url)
            let result = await withTaskGroup(of: Result.self) { group in
                group.addTask {
                    do { try await AppleSpeechService.prepare(); return .completed }
                    catch { let error = error as NSError; return .failed(error.domain, error.code) }
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(180)); return .timedOut }
                    catch { return .cancelled }
                }
                let first = await group.next() ?? .cancelled
                if case .timedOut = first {
                    var stop = receipt; stop.outcome = "deadline_cancel_requested"; try? save(stop, to: url)
                }
                group.cancelAll()
                return first
            }
            switch result {
            case .completed: receipt.outcome = "prepare_completed"
            case .timedOut: receipt.outcome = "prepare_timed_out"
            case .cancelled: receipt.outcome = "prepare_cancelled"
            case let .failed(domain, code):
                receipt.outcome = "prepare_failed"; receipt.errorDomain = domain; receipt.errorCode = code
            }
        }
        receipt.after = await snapshot()
        try save(receipt, to: url)
    }
}
