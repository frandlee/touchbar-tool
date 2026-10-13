import Foundation

struct SendObservation {
    let frontmostPID: Int32?
    let sameField: Bool
    let caretLocation: Int?
    let selectionLength: Int?
    let pastedText: String?
    let clipboardUnchanged: Bool
    let permissionsAvailable: Bool
    let enabled: Bool
}

enum SendDecision: Equatable { case idle, waiting, send, cancelled }

// Pure state machine; no input events, AX access, or application activation.
final class AutoSendGate {
    private struct Pending {
        let pid: Int32
        let text: String
        let insertionLocation: Int
        let earliest: TimeInterval
        let deadline: TimeInterval
        var confirmations: Int = 0
    }
    private var pending: Pending?
    private var lastBegin = -Double.infinity
    var isPending: Bool { pending != nil }

    @discardableResult
    func begin(pid: Int32, text: String, insertionLocation: Int,
               now: TimeInterval, delay: TimeInterval) -> Bool {
        guard pending == nil, now - lastBegin >= 0.6,
              pid > 0, insertionLocation >= 0, !text.isEmpty,
              insertionLocation <= Int.max - text.utf16.count,
              delay >= 0.2, delay <= 1.5 else { return false }
        pending = Pending(pid: pid, text: text, insertionLocation: insertionLocation,
                          earliest: now + delay, deadline: now + delay + 1.5)
        lastBegin = now
        return true
    }
    func cancel() { pending = nil }
    @discardableResult
    func focusNotification(sameField: Bool) -> Bool {
        guard pending != nil, !sameField else { return false }
        cancel()
        return true
    }

    func evaluate(_ observation: SendObservation, now: TimeInterval) -> SendDecision {
        guard var current = pending else { return .idle }
        guard observation.enabled, observation.permissionsAvailable,
              observation.frontmostPID == current.pid, observation.sameField,
              observation.clipboardUnchanged, now <= current.deadline else {
            pending = nil
            return .cancelled
        }
        let verified = observation.caretLocation == current.insertionLocation + current.text.utf16.count
            && observation.selectionLength == 0 && observation.pastedText == current.text
        current.confirmations = verified ? current.confirmations + 1 : 0
        guard verified, current.confirmations >= 2, now >= current.earliest else {
            pending = current
            return .waiting
        }
        // Consume before posting: this session can never request Return twice.
        pending = nil
        return .send
    }
}
