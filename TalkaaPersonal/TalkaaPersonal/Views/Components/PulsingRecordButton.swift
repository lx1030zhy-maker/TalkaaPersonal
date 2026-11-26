import SwiftUI

/// 中央脉冲波纹录音按钮（支持实时音量反馈、波形可视化与防误触锁定）
struct PulsingRecordButton: View {
    let isRecording: Bool
    let amplitude: Float
    let waveformSamples: [Float]
    let duration: TimeInterval
    @Binding var isLocked: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // 实时分贝波形条
            if isRecording {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(waveformSamples.enumerated()), id: \.offset) { _, sample in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red.gradient)
                            .frame(width: 4, height: max(6, CGFloat(sample) * 44))
                            .animation(.interpolatingSpring(stiffness: 220, damping: 20), value: sample)
                    }
                }
                .frame(height: 46)
                .transition(.opacity.combined(with: .scale))

                Text(formatDuration(duration))
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.red)
            }

            // 按钮与防误触控制区
            HStack(spacing: 28) {
                if isRecording {
                    Button {
                        if !isLocked { onCancel() }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                            Text("重录")
                                .font(.caption2)
                        }
                        .foregroundStyle(isLocked ? Color.secondary.opacity(0.35) : Color.secondary)
                    }
                    .disabled(isLocked)
                }

                // 中央脉冲圆环
                ZStack {
                    if isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.16))
                            .frame(width: 96 + CGFloat(amplitude) * 34, height: 96 + CGFloat(amplitude) * 34)
                            .animation(.easeOut(duration: 0.08), value: amplitude)

                        Circle()
                            .stroke(Color.red.opacity(0.35), lineWidth: 2)
                            .frame(width: 86 + CGFloat(amplitude) * 20, height: 86 + CGFloat(amplitude) * 20)
                            .animation(.easeOut(duration: 0.08), value: amplitude)
                    }

                    Button {
                        if isRecording {
                            guard !isLocked else { return }
                            onStop()
                        } else {
                            onStart()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red.gradient : Color.indigo.gradient)
                                .frame(width: 76, height: 76)
                                .shadow(color: (isRecording ? Color.red : Color.indigo).opacity(0.35), radius: 12, y: 6)

                            if isRecording {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white)
                                    .frame(width: 24, height: 24)
                                    .opacity(isLocked ? 0.55 : 1.0)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
                }

                if isRecording {
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            isLocked.toggle()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .font(.title2)
                            Text(isLocked ? "已锁定" : "防误触")
                                .font(.caption2)
                        }
                        .foregroundStyle(isLocked ? .orange : .secondary)
                    }
                }
            }

            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var hintText: String {
        if !isRecording {
            return "轻点开始录制 .m4a 音频，完成后直连 Gemini 4 Neon 评分"
        }
        return isLocked ? "已开启防误触锁定，点击右侧锁图标解锁后可提交" : "录音中 · 点击中央方块结束并立即评分"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
