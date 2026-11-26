import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

@main
struct TalkaaLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TalkaaMockLiveActivityWidget()
    }
}

struct TalkaaMockLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TalkaaMockActivityAttributes.self) { context in
            // 锁屏与通知栏实时活动卡片
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: context.state.isSpeakingPhase ? "mic.fill" : "pencil.and.outline")
                        .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
                    Text(context.state.stageTitle)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
                }
                Text(context.attributes.topicTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isSpeakingPhase ? "陈述录音" : "构思笔记",
                          systemImage: context.state.isSpeakingPhase ? "waveform" : "timer")
                        .font(.caption.bold())
                        .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                        .font(.headline.monospacedDigit().bold())
                        .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.topicTitle)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.isSpeakingPhase ? "mic.fill" : "timer")
                    .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endTime, countsDown: true)
                    .font(.caption2.monospacedDigit().bold())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.isSpeakingPhase ? "mic.fill" : "timer")
                    .foregroundStyle(context.state.isSpeakingPhase ? .red : .indigo)
            }
        }
    }
}
#endif
