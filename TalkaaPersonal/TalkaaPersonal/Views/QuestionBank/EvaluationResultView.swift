import SwiftUI
import SwiftData

/// 四维精准评分报告 + 逐词标色发音纠正 + 音素诊断卡片 + 点词切片回放 & 跟读重练 + WPM 仪表盘
struct EvaluationResultView: View {
    @Environment(\.modelContext) private var modelContext
    let record: PracticeRecord

    @State private var audioManager = AudioManager()
    @State private var selectedWord: WordAnalysisItem?
    @State private var savedExpressions: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 总分与音频总回放头卡
                overallHeaderCard

                // 2. 语速 (WPM) 与停顿仪表盘
                pacingGaugeCard

                // 3. 逐词标色文本（点击红/黄词弹出音素级诊断卡片 + 切片回放）
                wordLevelPronunciationCard

                // 4. 四维官方评分明细
                fourDimensionsSection

                // 5. 地道表达升级（一键收藏至提分素材库）
                if !record.upgradedExpressions.isEmpty {
                    upgradedExpressionsCard
                }

                // 6. 语法纠错清单
                if !record.grammarCorrections.isEmpty {
                    grammarCorrectionsCard
                }

                // 7. Band 8 高分示范答案
                if !record.band8SampleAnswer.isEmpty {
                    band8SampleCard
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("AI 四维诊断报告")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedWord) { wordItem in
            WordDiagnosticSheet(
                wordItem: wordItem,
                audioURL: record.audioFileURL,
                audioManager: audioManager
            )
            .presentationDetents([.medium, .large])
        }
        .onDisappear {
            audioManager.stopAllPlayback()
        }
    }

    // MARK: - 1. 总分卡

    private var overallHeaderCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IELTS 预估总分")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", record.overallBand))
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(.indigo)
                        Text("/ 9.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = record.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        if audioManager.isPlayingAudio && !audioManager.isPlayingSegment {
                            audioManager.stopAudioPlayer()
                        } else {
                            audioManager.playFullAudio(url: url)
                        }
                    } label: {
                        Label(audioManager.isPlayingAudio && !audioManager.isPlayingSegment ? "停止回放" : "听完整原声",
                              systemImage: audioManager.isPlayingAudio && !audioManager.isPlayingSegment ? "stop.circle.fill" : "play.circle.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.indigo)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }

            // 四维小分横条
            HStack(spacing: 8) {
                ScorePill(title: "流利度", score: record.fluencyScore, color: .blue)
                ScorePill(title: "发音", score: record.pronunciationScore, color: .purple)
                ScorePill(title: "词汇", score: record.lexicalScore, color: .teal)
                ScorePill(title: "语法", score: record.grammarScore, color: .orange)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 2. 语速与停顿仪表盘

    private var pacingGaugeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("语速与停顿仪表盘", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                Text(wpmBadgeText)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(wpmBadgeColor.opacity(0.16))
                    .foregroundStyle(wpmBadgeColor)
                    .clipShape(Capsule())
            }

            // WPM 进度条（理想区间 120-150 WPM）
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let minWPM: Double = 60
                    let maxWPM: Double = 200
                    let clamped = min(max(Double(record.wpm), minWPM), maxWPM)
                    let markerX = ((clamped - minWPM) / (maxWPM - minWPM)) * geo.size.width
                    let idealStart = ((120.0 - minWPM) / (maxWPM - minWPM)) * geo.size.width
                    let idealWidth = ((150.0 - 120.0) / (maxWPM - minWPM)) * geo.size.width

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.secondarySystemFill))
                            .frame(height: 12)

                        // 120-150 WPM 绿色理想区间
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.45))
                            .frame(width: idealWidth, height: 12)
                            .offset(x: idealStart)

                        // 当前语速指针
                        Circle()
                            .fill(wpmBadgeColor)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .offset(x: max(0, min(geo.size.width - 18, markerX - 9)))
                    }
                }
                .frame(height: 20)

                HStack {
                    Text("偏慢 (<120)")
                    Spacer()
                    Text("理想区间 120–150 WPM").bold().foregroundStyle(.green)
                    Spacer()
                    Text("偏快 (>150)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                MetricBox(title: "平均语速", value: "\(record.wpm) WPM", icon: "speedometer")
                MetricBox(title: "异常长停顿", value: "\(record.longPausesCount) 次", icon: "pause.circle")
                MetricBox(title: "作答时长", value: "\(Int(record.durationSeconds)) 秒", icon: "clock")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var wpmBadgeText: String {
        if record.wpm < 120 { return "偏慢 · 建议提升连贯性" }
        if record.wpm <= 150 { return "理想语速区间" }
        return "偏快 · 注意吞音风险"
    }

    private var wpmBadgeColor: Color {
        if record.wpm < 120 { return .orange }
        if record.wpm <= 150 { return .green }
        return .red
    }

    // MARK: - 3. 逐词发音纠正文本

    private var wordLevelPronunciationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("逐词发音诊断（点击单词回放原声）", systemImage: "waveform.and.magnifyingglass")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 14) {
                LegendDot(color: .green, label: "发音准确")
                LegendDot(color: .orange, label: "重音/弱读偏差")
                LegendDot(color: .red, label: "音素明显错误")
            }
            .font(.caption2)

            if record.wordAnalysis.isEmpty {
                Text("本次评分未返回逐词时间戳数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 8) {
                    ForEach(record.wordAnalysis) { item in
                        Button {
                            selectedWord = item
                            if let url = record.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
                                audioManager.playSegment(url: url, startMs: item.startMs, endMs: item.endMs)
                            }
                        } label: {
                            Text(item.word)
                                .font(.callout.weight(item.status == .accurate ? .regular : .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(color(for: item.status).opacity(0.15))
                                .foregroundStyle(color(for: item.status))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func color(for status: PronunciationStatus) -> Color {
        switch status {
        case .accurate: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    // MARK: - 4. 四维明细点评

    private var fourDimensionsSection: some View {
        VStack(spacing: 12) {
            CriterionDetailCard(title: "1. Fluency & Coherence (流利度与连贯性)", score: record.fluencyScore, feedback: record.fluencyFeedbackZh, tint: .blue)
            CriterionDetailCard(title: "2. Pronunciation (发音表现)", score: record.pronunciationScore, feedback: record.pronunciationFeedbackZh, tint: .purple)
            CriterionDetailCard(title: "3. Lexical Resource (词汇多样性)", score: record.lexicalScore, feedback: record.lexicalFeedbackZh, tint: .teal)
            CriterionDetailCard(title: "4. Grammatical Range & Accuracy (语法广度与准确性)", score: record.grammarScore, feedback: record.grammarFeedbackZh, tint: .orange)
        }
    }

    // MARK: - 5. 词汇升级建议

    private var upgradedExpressionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("高分词汇与地道搭配升级", systemImage: "sparkles")
                .font(.headline)
            ForEach(record.upgradedExpressions, id: \.self) { expr in
                HStack {
                    Text(expr)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        saveExpressionToVault(expr)
                    } label: {
                        Image(systemName: savedExpressions.contains(expr) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(.indigo)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 6. 语法纠错清单

    private var grammarCorrectionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("语法精准定位与修改", systemImage: "text.badge.checkmark")
                .font(.headline)
            ForEach(record.grammarCorrections) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("原句：\(item.original)")
                        .font(.subheadline)
                        .strikethrough()
                        .foregroundStyle(.red)
                    Text("建议：\(item.corrected)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Text("解析：\(item.reasonZh)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 7. Band 8 示范答案

    private var band8SampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Band 8.0+ 高分示范回答", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Spacer()
                Button {
                    audioManager.speakEnglish(record.band8SampleAnswer)
                } label: {
                    Label("朗读示范", systemImage: "speaker.wave.2.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

            Text(record.band8SampleAnswer)
                .font(.body)
                .lineSpacing(5)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func saveExpressionToVault(_ expr: String) {
        guard !savedExpressions.contains(expr) else { return }
        let vaultItem = StudyVaultItem(
            category: "我的收藏",
            partScope: record.part.shortTitle,
            titleEn: expr,
            meaningZh: "来自练习反馈升级表达（\(record.promptSnapshot.prefix(24))...）",
            exampleEn: String(record.band8SampleAnswer.prefix(120)) + "...",
            isFavorite: true
        )
        modelContext.insert(vaultItem)
        try? modelContext.save()
        savedExpressions.insert(expr)
    }
}

// MARK: - 音素级诊断卡片（含点词原声切片回放 + 标准音对照 + 单句跟读重练）

private struct WordDiagnosticSheet: View {
    let wordItem: WordAnalysisItem
    let audioURL: URL?
    let audioManager: AudioManager

    @State private var shadowURL: URL?
    @State private var isRecordingShadow = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(wordItem.word)
                        .font(.largeTitle.bold())
                    if !wordItem.ipaTarget.isEmpty {
                        Text(wordItem.ipaTarget)
                            .font(.title3.monospaced())
                            .foregroundStyle(.indigo)
                    }
                    Spacer()
                    Text("\(wordItem.startMs)–\(wordItem.endMs) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // 音素与口腔纠音说明
                VStack(alignment: .leading, spacing: 8) {
                    Label("音素诊断与口腔纠音技巧", systemImage: "mouth")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(wordItem.issueZh.isEmpty ? "该词发音清晰准确，重音位置与元音饱满度符合雅思高分要求！" : wordItem.issueZh)
                        .font(.body)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // 点词回放 vs 标准发音对照
                HStack(spacing: 12) {
                    Button {
                        if let url = audioURL {
                            audioManager.playSegment(url: url, startMs: wordItem.startMs, endMs: wordItem.endMs)
                        }
                    } label: {
                        Label("回放我的原声", systemImage: "waveform")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(audioURL == nil)

                    Button {
                        audioManager.speakEnglish(wordItem.word, rate: 0.40)
                    } label: {
                        Label("听标准发音", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // 单句/单词跟读重练模块
                VStack(alignment: .leading, spacing: 10) {
                    Text("单句/单词跟读重练")
                        .font(.subheadline.bold())

                    HStack(spacing: 12) {
                        Button {
                            if isRecordingShadow {
                                if let res = audioManager.stopRecording() {
                                    shadowURL = res.url
                                }
                                isRecordingShadow = false
                            } else {
                                Task {
                                    isRecordingShadow = true
                                    _ = await audioManager.startRecording(filePrefix: "shadow_\(wordItem.word)")
                                }
                            }
                        } label: {
                            Label(isRecordingShadow ? "停止跟读录音" : "开始跟读重练",
                                  systemImage: isRecordingShadow ? "stop.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecordingShadow ? .red : .teal)

                        if let shadowURL {
                            Button {
                                audioManager.playFullAudio(url: shadowURL)
                            } label: {
                                Label("听重练对比", systemImage: "play.fill")
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 14)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("音素级诊断卡片")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 辅助小组件

private struct ScorePill: View {
    let title: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", score))
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MetricBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.indigo)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

private struct CriterionDetailCard: View {
    let title: String
    let score: Double
    let feedback: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "Band %.1f", score))
                    .font(.subheadline.bold().monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
            Text(feedback)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
