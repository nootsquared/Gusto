import Foundation

public struct DemoService: Sendable {
    public var delayNanoseconds: UInt64
    public init(delayNanoseconds: UInt64 = 700_000_000) { self.delayNanoseconds = delayNanoseconds }
    public func pause() async throws {
        try Task.checkCancellation()
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
    }
    public func reply(to text: String) -> String {
        switch text {
        case "Still available?": return "Yes, all yours."
        case "Fresh photo?": return "Condition reconfirmed just now — still good."
        case "I'm here": return "Coming out now!"
        case "+10 min": return "No problem, see you then."
        case "Reschedule": return "Tomorrow 9 AM works too."
        default: return "Sounds good! See you at pickup."
        }
    }
}
