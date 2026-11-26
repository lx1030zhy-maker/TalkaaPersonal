import SwiftUI
import SwiftData

/// 1:1 全真模拟考试状态机（Stage 1 Part 1 -> Stage 2 Part 2 灵动岛 -> Stage 3 Part 3 动态追问 -> 全真模考成绩单）
struct MockExamView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allQuestions: [IELTSQuestion]
    @Query(sort: \MockExamSessionRecord.createdAt, order: .reverse) private var mockHistory: [MockExamSessionRecord]

    enum ExamPhase: Equatable {
        case idle
        case part1(questionIndex: Int)
        case part2Prep(remaining: Int)
        case part2Speaking(remaining: Int)
        case generatingPart3
        case part3(questionIndex: Int)
        case evaluatingFinal
        case completed
    }

    @State private var phase: ExamPhase = .idle
    @State private var audioManager = AudioManager()
    @State private var isLocked = false

    // 当次模考状态数据
    @State private var examStartDate = Date()
    @State private var part1Questions: [String] = []
    @State private var part1TopicNames: [String] = []
    @State private var part2Question: IELTSQuestion?
    @State private var part2Notes = ""
    @State private var part2AudioURL: URL?
    @State private var part3Questions: [String] = []
    @State private var collectedAudioURLs: [URL] = []

    @State private var timerTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var latestMockRecord: MockExamSessionRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    switch phase {
                    case .idle:
                        idleLandingSection
                        historySection
                    case .part1(let index):
                        stageHeader(stage: "Stage 1 / 3 · Part 1 日常问答", progress: Double(index + 1) / Double(max(1, part1Questions.count)))
                        examinerPromptCard(
                            badge: "第 \(index + 1) / \(part1Questions.count) 题",
                            text: part1Questions.indices.contains(index) ? part1Questions[index] : ""
                        )
                        mockRecorderCard(nextActionTitle: index + 1 < part1Questions.count ? "提交并进入下一问" : "完成 Part 1，进入 Part 2") { url in
                            collectedAudioURLs.append(url)
                            if index + 1 < part1Questions.count {
                                advanceToPart1(index: index + 1)
                            } else {
                                startPart2Prep()
                            }
                        }
                    case .part2Prep(let remaining):
                        stageHeader(stage: "Stage 2 / 3 · Part 2 1分钟强制准备", progress: Double(60 - remaining) / 60.0)
                        part2CueCardView(countdown: remaining, isSpeaking: false)
                    case .part2Speaking(let remaining):
                        stageHeader(stage: "Stage 2 / 3 · Part 2 2分钟陈述录音", progress: Double(120 - remaining) / 120.0)
                        part2CueCardView(countdown: remaining, isSpeaking: true)
                    case .generatingPart3:
                        loadingCard(
                            title: "AI 考官正在聆听您的 Part 2 陈述...",
                            subtitle: "Gemini 4 Neon 正在结合您的回答细节动态生成 4–5 道 Part 3 深度追问"
                        )
                    case .part3(let index):
                        stageHeader(stage: "Stage 3 / 3 · Part 3 考官动态追问", progress: Double(index + 1) / Double(max(1, part3Questions.count)))
                        examinerPromptCard(
                            badge: "追问 \(index + 1) / \(part3Questions.count)",
                            text: part3Questions.indices.contains(index) ? part3Questions[index] : ""
                        )
                        mockRecorderCard(nextActionTitle: index + 1 < part3Questions.count ? "提交并听下一追问" : "结束模考并生成成绩单") { url in
                            collectedAudioURLs.append(url)
                            if index + 1 < part3Questions.count {
                                advanceToPart3(index: index + 1)
                            } else {
                                finishAndEvaluateMockExam()
                            }
                        }
                    case .evaluatingFinal:
                        loadingCard(
                            title: "正在汇总三阶段音频生成《全真模考成绩单》...",
                            subtitle: "直连 Gemini 4 Neon 进行全维度流利度、发音、词汇与语法综合评分"
                        )
                    case .completed:
                        if let record = latestMockRecord {
                            MockExamReportCard(record: record)
                            Button("返回模考大厅") {
                                resetExam()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("1:1 全真模拟考试")
            .toolbar {
                if phase != .idle && phase != .completed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("退出模考", role: .destructive) {
                            resetExam()
                        }
                    }
                }
            }
            .onDisappear {
                timerTask?.cancel()
                LiveActivityManager.shared.endCountdown()
                audioManager.stopAllPlayback()
            }
        }
    }

    // MARK: - 模考大厅

    private var idleLandingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "graduationcap.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("全真雅思口语考场 1:1 复刻")
                        .font(.title3.bold())
                    Text("全程 AI 考官语音提问 · 灵动岛同步计时 · 归档完整成绩单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                stageBullet(num: "1", title: "Stage 1 · Part 1 日常问答", desc: "随机抽取 2–3 个当季话题共 6 题，AI 考官语音连续发问。")
                stageBullet(num: "2", title: "Stage 2 · Part 2 话题卡陈述", desc: "强制 1 分钟准备倒计时（可记笔记 + 灵动岛显示）→ 提示音后自动开启 2 分钟陈述录音。")
                stageBullet(num: "3", title: "Stage 3 · Part 3 动态深度追问", desc: "Gemini 4 Neon 实时听取您的 Part 2 内容，针对性追问 4–5 道抽象问题。")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button {
                startFullMockExam()
            } label: {
                Label("立即开始全真模考", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("历史全真模考归档")
                .font(.headline)
            if mockHistory.isEmpty {
                Text("暂无模考记录，完成首次全真模考后将永久归档于此。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(mockHistory) { record in
                    NavigationLink(destination: ScrollView { MockExamReportCard(record: record).padding() }.background(Color(.systemGroupedBackground)).navigationTitle("模考成绩单")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.part2TopicTitle)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · 耗时 \(Int(record.totalDurationSeconds / 60)) 分钟")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "Band %.1f", record.overallBand))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.indigo)
                        }
                        .padding(14)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 考试阶段 UI 组件

    private func stageHeader(stage: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stage)
                .font(.subheadline.bold())
                .foregroundStyle(.indigo)
            ProgressView(value: min(max(progress, 0), 1))
                .tint(.indigo)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func examinerPromptCard(badge: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(badge)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.14))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    audioManager.speakEnglish(text)
                } label: {
                    Label("重听考官提问", systemImage: "speaker.wave.2.fill")
                        .font(.caption.bold())
                }
            }
            Text(text)
                .font(.title3.bold())
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func mockRecorderCard(nextActionTitle: String, onRecorded: @escaping (URL) -> Void) -> some View {
        VStack(spacing: 12) {
            PulsingRecordButton(
                isRecording: audioManager.isRecording,
                amplitude: audioManager.currentAmplitude,
                waveformSamples: audioManager.waveformSamples,
                duration: audioManager.recordingDuration,
                isLocked: $isLocked,
                onStart: {
                    Task { _ = await audioManager.startRecording(filePrefix: "mock") }
                },
                onStop: {
                    isLocked = false
                    if let res = audioManager.stopRecording() {
                        onRecorded(res.url)
                    }
                },
                onCancel: {
                    isLocked = false
                    audioManager.cancelRecording()
                }
            )
            Text(nextActionTitle)
                .font(.caption)
                .foregroundStyle(.indigo)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func part2CueCardView(countdown: Int, isSpeaking: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isSpeaking ? "2分钟陈述录音中（灵动岛已同步）" : "1分钟准备倒计时（灵动岛已同步）",
                      systemImage: isSpeaking ? "mic.fill" : "timer")
                    .font(.subheadline.bold())
                    .foregroundStyle(isSpeaking ? .red : .indigo)
                Spacer()
                Text(String(format: "%02d:%02d", countdown / 60, countdown % 60))
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(isSpeaking ? .red : .indigo)
            }

            if let q = part2Question {
                Text(q.topicTitle)
                    .font(.headline)
                ForEach(q.cueCardBullets, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("考场草稿纸")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("快速写下关键词与结构提纲...", text: $part2Notes, axis: .vertical)
                .lineLimit(4...6)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if isSpeaking {
                HStack(spacing: 4) {
                    ForEach(Array(audioManager.waveformSamples.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red.gradient)
                            .frame(width: 4, height: max(6, CGFloat(s) * 36))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)

                Button {
                    completePart2Speaking()
                } label: {
                    Text("提前结束陈述并进入 Part 3")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("跳过剩余准备时间，立即开始 2 分钟陈述") {
                    startPart2Speaking()
                }
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func loadingCard(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func stageBullet(num: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.indigo)
                .foregroundStyle(.white)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 状态机流转逻辑

    private func startFullMockExam() {
        errorMessage = nil
        collectedAudioURLs = []
        part2Notes = ""
        part2AudioURL = nil
        part3Questions = []
        examStartDate = Date()

        // 随机抽取 2–3 个 Part 1 话题，共计 6 题
        let p1Pool = allQuestions.filter { $0.part == .part1 }.shuffled()
        let pickedP1 = Array(p1Pool.prefix(3))
        part1TopicNames = pickedP1.map(\.topicTitle)
        var qList: [String] = []
        for topic in pickedP1 {
            qList.append(contentsOf: topic.subQuestions.prefix(2))
        }
        if qList.isEmpty {
            qList = [
                "Do you work or are you a student?",
                "What do you like most about your hometown?",
                "Which mobile app do you use most frequently every day?",
                "Do you prefer drinking coffee or tea?"
            ]
        }
        part1Questions = Array(qList.prefix(6))

        // 随机抽取 1 道 Part 2 话题卡
        part2Question = allQuestions.filter { $0.part == .part2 }.randomElement()

        advanceToPart1(index: 0)
    }

    private func advanceToPart1(index: Int) {
        phase = .part1(questionIndex: index)
        if part1Questions.indices.contains(index) {
            audioManager.speakEnglish(part1Questions[index])
        }
    }

    private func startPart2Prep() {
        timerTask?.cancel()
        phase = .part2Prep(remaining: 60)
        let title = part2Question?.topicTitle ?? "Part 2 Cue Card"
        audioManager.speakEnglish("Now let's move on to Part 2. You have one minute to prepare your talk about: \(title).")
        LiveActivityManager.shared.startPart2Countdown(topicTitle: title, isSpeakingPhase: false, durationSeconds: 60)

        timerTask = Task {
            var remaining = 60
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                phase = .part2Prep(remaining: remaining)
            }
            if !Task.isCancelled {
                startPart2Speaking()
            }
        }
    }

    private func startPart2Speaking() {
        timerTask?.cancel()
        phase = .part2Speaking(remaining: 120)
        let title = part2Question?.topicTitle ?? "Part 2 Cue Card"
        LiveActivityManager.shared.startPart2Countdown(topicTitle: title, isSpeakingPhase: true, durationSeconds: 120)

        audioManager.speakEnglish("Your one minute preparation time is over. Please start speaking now.") {
            Task { @MainActor in
                _ = await audioManager.startRecording(filePrefix: "mock_part2")
            }
        }

        timerTask = Task {
            var remaining = 120
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                phase = .part2Speaking(remaining: remaining)
            }
            if !Task.isCancelled {
                completePart2Speaking()
            }
        }
    }

    private func completePart2Speaking() {
        timerTask?.cancel()
        LiveActivityManager.shared.endCountdown()
        if let res = audioManager.stopRecording() {
            part2AudioURL = res.url
            collectedAudioURLs.append(res.url)
        }
        phase = .generatingPart3

        Task {
            do {
                if let p2URL = part2AudioURL {
                    let followUp = try await GeminiNeonService.shared.generatePart3FollowUpQuestions(
                        part2AudioURL: p2URL,
                        part2TopicTitle: part2Question?.topicTitle ?? "General Topic"
                    )
                    part3Questions = Array(followUp.questions.prefix(5))
                }
                if part3Questions.isEmpty {
                    part3Questions = fallbackPart3Questions()
                }
                advanceToPart3(index: 0)
            } catch {
                // 若网络或 Key 未配置导致动态追问失败，降级使用题库 Part 3 并提示
                errorMessage = "动态追问生成降级（\(error.localizedDescription)），已自动切换题库 Part 3 继续模考。"
                part3Questions = fallbackPart3Questions()
                advanceToPart3(index: 0)
            }
        }
    }

    private func advanceToPart3(index: Int) {
        phase = .part3(questionIndex: index)
        if part3Questions.indices.contains(index) {
            audioManager.speakEnglish(part3Questions[index])
        }
    }

    private func finishAndEvaluateMockExam() {
        phase = .evaluatingFinal
        Task {
            do {
                let dto = try await GeminiNeonService.shared.evaluateFullMockExam(
                    audioURLs: collectedAudioURLs,
                    part1Summary: part1TopicNames.joined(separator: "、"),
                    part2Topic: part2Question?.topicTitle ?? "Part 2 Topic",
                    part3Questions: part3Questions
                )

                let totalDuration = Date().timeIntervalSince(examStartDate)
                let record = MockExamSessionRecord(
                    totalDurationSeconds: totalDuration,
                    part1TopicsSummary: part1TopicNames.joined(separator: "、"),
                    part2TopicTitle: part2Question?.topicTitle ?? "Part 2 Topic",
                    part2Notes: part2Notes,
                    part3Questions: part3Questions,
                    audioFileNames: collectedAudioURLs.map(\.lastPathComponent),
                    dto: dto
                )
                modelContext.insert(record)
                try? modelContext.save()

                latestMockRecord = record
                phase = .completed
            } catch {
                errorMessage = "模考评分失败：\(error.localizedDescription)"
                phase = .idle
            }
        }
    }

    private func fallbackPart3Questions() -> [String] {
        allQuestions.filter { $0.part == .part3 }.randomElement()?.subQuestions ?? [
            "How have people's attitudes toward this topic changed over the past two decades?",
            "Do you think younger and older generations view this differently?",
            "What role should education or government play in addressing related challenges?",
            "How might technology reshape this aspect of society in the future?"
        ]
    }

    private func resetExam() {
        timerTask?.cancel()
        audioManager.stopAllPlayback()
        if audioManager.isRecording { audioManager.cancelRecording() }
        LiveActivityManager.shared.endCountdown()
        phase = .idle
        errorMessage = nil
    }
}

// MARK: - 《全真模考成绩单》视图组件

struct MockExamReportCard: View {
    let record: MockExamSessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                Text("IELTS 全真模拟考试成绩单")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(String(format: "Band %.1f", record.overallBand))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(.indigo)
                Text("平均语速 \(record.wpm) WPM · 异常停顿 \(record.longPausesCount) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            RadarChartView(
                fluency: record.fluencyScore,
                pronunciation: record.pronunciationScore,
                lexical: record.lexicalScore,
                grammar: record.grammarScore
            )
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 8) {
                Text("本场考题回顾").font(.headline)
                Text("• Part 1：\(record.part1TopicsSummary)").font(.subheadline)
                Text("• Part 2：\(record.part2TopicTitle)").font(.subheadline)
                Text("• Part 3 动态追问（\(record.part3Questions.count) 题）：").font(.subheadline.bold())
                ForEach(record.part3Questions, id: \.self) { q in
                    Text("   - \(q)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                Text("考官四维深度点评").font(.headline)
                feedbackBlock("流利度与连贯性 (\(String(format: "%.1f", record.fluencyScore)))", record.fluencyFeedbackZh)
                feedbackBlock("发音表现 (\(String(format: "%.1f", record.pronunciationScore)))", record.pronunciationFeedbackZh)
                feedbackBlock("词汇多样性 (\(String(format: "%.1f", record.lexicalScore)))", record.lexicalFeedbackZh)
                feedbackBlock("语法广度与准确性 (\(String(format: "%.1f", record.grammarScore)))", record.grammarFeedbackZh)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func feedbackBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.indigo)
            Text(body).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
