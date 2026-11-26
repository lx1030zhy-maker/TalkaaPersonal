import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct TalkaaMockActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var stageTitle: String     // "Part 2 · 1分钟准备" | "Part 2 · 2分钟陈述"
        var endTime: Date
        var isSpeakingPhase: Bool
    }

    var topicTitle: String
}
#endif
