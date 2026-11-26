import SwiftUI
import SwiftData

struct PracticeSessionView: View {
    @Environment(\.modelContext) private var modelContext
    let question: IELTSQuestion

    @State private var audioManager = AudioManager()
    @State private var selectedSubQuestionIndex = 0
    @State private var isLocked = false
    @State private var isEvaluating = false
    @State private var evaluationError: String?
    @State private var latestRecord: PracticeRecord?
    @State private var showingCustomAnswerSheet = false

    // Part 2 1分钟准备 + 2分钟陈述倒计时
    @State private var prepRemaining = 60
    @State private var isPrepping = false
    @State private var prepNotes = ""
    @State private var prepTimerTask: Task<Void, Never>?

    private var activePromptText: String {
        if !question.subQuestions.isEmpty, selectedSubQuestionIndex < question.subQuestions.count {
            return question.subQuestions[selectedSubQuestionIndex]
        }
        return question.promptText
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 题目卡片
                questionCard

                // Part 2 专属准备区（1分钟倒计时 + 笔记 + 灵动岛同步）
                if question.part == .part2 {
                    part2PrepCard
                }

                // 录音操作区
                VStack(spacing: 12) {
                    if isEvaluating {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("正在直连 Gemini 4 Neon 聆听您的 .m4a 原始语音...")
                                .font(.subheadline.bold())
                            Text("执行四维官方评分 + 逐词毫秒级时间戳纠音")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                    } else {
                        PulsingRecordButton(
                            isRecording: audioManager.isRecording,
                            amplitude: audioManager.currentAmplitude,
                            waveformSamples: audioManager.waveformSamples,
                            duration: audioManager.recordingDuration,
                            isLocked: $isLocked,
                            onStart: {
                                stopPrepTimer()
                                Task {
                                    _ = await audioManager.startRecording(filePrefix: question.questionCode)
                                    if question.part == .part2 {
                                        LiveActivityManager.shared.startPart2Countdown(
                                            topicTitle: question.topicTitle,
                                            isSpeakingPhase: true,
                                            durationSeconds: 120
                                        )
                                    }
                                }
                            },
                            onStop: {
                                isLocked = false
                                LiveActivityManager.shared.endCountdown()
                                if let result = audioManager.stopRecording() {
                                    submitForEvaluation(audioURL: result.url, duration: result.duration)
                                }
                            },
                            onCancel: {
                                isLocked = false
                                LiveActivityManager.shared.endCountdown()
                                audioManager.cancelRecording()
                            }
                        )
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // 错误提示
                if let err = evaluationError ?? audioManager.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 历史练习记录
                if !question.practiceRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("本题历史评分记录")
                            .font(.headline)
                        ForEach(question.practiceRecords.sorted(by: { $0.createdAt > $1.createdAt })) { record in
                            NavigationLink(destination: EvaluationResultView(record: record)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline.bold())
                                        Text("语速 \(record.wpm) WPM · 停顿 \(record.longPausesCount) 次")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "Band %.1f", record.overallBand))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.indigo)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
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
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(question.part.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCustomAnswerSheet = true
                } label: {
                    Label("定制答案", systemImage: "wand.and.stars")
                }
            }
        }
        .navigationDestination(item: $latestRecord) { record in
            EvaluationResultView(record: record)
        }
        .sheet(isPresented: $showingCustomAnswerSheet) {
            NavigationStack {
                CustomAnswerView(preselectedQuestion: question)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { showingCustomAnswerSheet = false }
                        }
                    }
            }
        }
        .onDisappear {
            stopPrepTimer()
            audioManager.stopAllPlayback()
            LiveActivityManager.shared.endCountdown()
        }
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(question.category)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    audioManager.speakEnglish(activePromptText)
                } label: {
                    Label(audioManager.isSpeakingTTS ? "朗读中..." : "AI 考官读题",
                          systemImage: audioManager.isSpeakingTTS ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Text(question.topicTitle)
                .font(.title3.bold())

            Text(activePromptText)
                .font(.body)
                .foregroundStyle(.primary)

            // Part 2 Cue Card 要点
            if !question.cueCardBullets.isEmpty {
                Divider()
                Text("You should say:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(question.cueCardBullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .padding(.top, 6)
                            .foregroundStyle(.indigo)
                        Text(bullet)
                            .font(.subheadline)
                    }
                }
            }

            // Part 1 / Part 3 题组内子题切换
            if !question.subQuestions.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(question.subQuestions.enumerated()), id: \.offset) { idx, _ in
                            Button("第 \(idx + 1) 问") {
                                selectedSubQuestionIndex = idx
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedSubQuestionIndex == idx ? Color.indigo : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedSubQuestionIndex == idx ? .white : .primary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var part2PrepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Part 2 · 1 分钟准备与草稿纸", systemImage: "timer")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "00:%02d", prepRemaining))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isPrepping ? .orange : .secondary)
                Button(isPrepping ? "停止" : "开始1分钟计时") {
                    if isPrepping {
                        stopPrepTimer()
                    } else {
                        startPrepTimer()
                    }
                }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }

            TextField("在此快速记录关键词（如：人物特征、转折事件、感受...）", text: $prepNotes, axis: .vertical)
                .lineLimit(3...5)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func startPrepTimer() {
        prepRemaining = 60
        isPrepping = true
        LiveActivityManager.shared.startPart2Countdown(
            topicTitle: question.topicTitle,
            isSpeakingPhase: false,
            durationSeconds: 60
        )
        prepTimerTask?.cancel()
        prepTimerTask = Task {
            while prepRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                prepRemaining -= 1
            }
            if !Task.isCancelled {
                isPrepping = false
                audioManager.speakEnglish("Your one minute preparation time is up. Please begin speaking.")
            }
        }
    }

    private func stopPrepTimer() {
        prepTimerTask?.cancel()
        prepTimerTask = nil
        isPrepping = false
    }

    private func submitForEvaluation(audioURL: URL, duration: TimeInterval) {
        isEvaluating = true
        evaluationError = nil

        Task {
            do {
                let dto = try await GeminiNeonService.shared.evaluateAudioAnswer(
                    audioURL: audioURL,
                    part: question.part,
                    topicTitle: question.topicTitle,
                    promptText: activePromptText,
                    cueCardBullets: question.cueCardBullets
                )
                let record = PracticeRecord(
                    audioFileName: audioURL.lastPathComponent,
                    durationSeconds: duration,
                    promptSnapshot: activePromptText,
                    part: question.part,
                    dto: dto,
                    question: question
                )
                question.isPracticed = true
                modelContext.insert(record)
                try? modelContext.save()

                isEvaluating = false
                latestRecord = record
            } catch {
                isEvaluating = false
                evaluationError = error.localizedDescription
            }
        }
    }
}
