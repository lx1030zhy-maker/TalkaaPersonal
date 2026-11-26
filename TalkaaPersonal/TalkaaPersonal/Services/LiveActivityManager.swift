import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// iPhone 17 灵动岛（ActivityKit Live Activity）Part 2 倒计时管理器
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    #if canImport(ActivityKit)
    private var currentActivity: Activity<TalkaaMockActivityAttributes>?
    #endif

    private init() {}

    func startPart2Countdown(topicTitle: String, isSpeakingPhase: Bool, durationSeconds: TimeInterval) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let endTime = Date().addingTimeInterval(durationSeconds)
        let state = TalkaaMockActivityAttributes.ContentState(
            stageTitle: isSpeakingPhase ? "Part 2 · 2分钟陈述" : "Part 2 · 1分钟准备",
            endTime: endTime,
            isSpeakingPhase: isSpeakingPhase
        )

        if let existing = currentActivity {
            Task {
                await existing.update(ActivityContent(state: state, staleDate: endTime))
            }
        } else {
            let attributes = TalkaaMockActivityAttributes(topicTitle: topicTitle)
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: endTime),
                    pushType: nil
                )
            } catch {
                print("Live Activity 启动失败: \(error)")
            }
        }
        #endif
    }

    func endCountdown() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.currentActivity = nil
        }
        #endif
    }
}
