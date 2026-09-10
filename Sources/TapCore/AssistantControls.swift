import Foundation

public enum AssistantIntent: String, CaseIterable {
    case accept = "Approve once", reject = "Reject", dictation = "Dictation"
}
public enum AssistantControls {
    public static func isChatGPTPage(_ url: String) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        return parsed.scheme == "https" && parsed.host?.lowercased() == "chatgpt.com"
    }
    public static let acceptLabels: Set<String> = ["approve", "approve once", "allow once", "accept"]
    public static let rejectLabels: Set<String> = ["reject", "decline", "deny", "deny once"]
    public static let dictationLabels: Set<String> = ["start dictation", "stop dictation", "dictate"]
    public static func match(_ intent: AssistantIntent, labels: [[String]]) -> Int? {
        let normalized = labels.map { Set($0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) }
        func matches(_ allowed: Set<String>) -> [Int] {
            normalized.indices.filter { !normalized[$0].isDisjoint(with: allowed) }
        }
        let accept = matches(acceptLabels), reject = matches(rejectLabels)
        switch intent {
        case .accept: return accept.count == 1 && reject.count == 1 && accept[0] != reject[0] ? accept[0] : nil
        case .reject: return accept.count == 1 && reject.count == 1 && accept[0] != reject[0] ? reject[0] : nil
        case .dictation:
            guard accept.isEmpty && reject.isEmpty else { return nil }
            let candidates = matches(dictationLabels)
            return candidates.count == 1 ? candidates[0] : nil
        }
    }
}
