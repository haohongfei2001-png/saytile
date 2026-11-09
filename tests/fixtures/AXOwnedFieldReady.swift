import Foundation
@testable import SaytileKit

/// Both callers have already restricted the resolver to a fresh fixture PID and document.
/// Read-only setup after the fixture changes focus. Never rebinds or repeats a write.
@MainActor func waitForOwnedField(_ access: AXInputAccess, original: String,
                                  caret: Int, pid: Int32) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    var last: InputTargetSnapshot?
    var consecutive = 0
    while clock.now < deadline {
        if let current = try? access.snapshot(), current.processID == pid,
           current.isEditable, !current.isSensitive, current.canSetSelectedText,
           current.selectionLocation == caret, current.selectionLength == 0,
           !current.isWeb || (current.pageContextComplete && current.pageIdentity != nil),
           access.textWitness(at: current) == original {
            consecutive = current == last ? consecutive + 1 : 1
            last = current
            if consecutive >= 3 { return }
        } else {
            last = nil
            consecutive = 0
        }
        try await Task.sleep(for: .milliseconds(180))
    }
    throw CocoaError(.validationMissingMandatoryProperty)
}
