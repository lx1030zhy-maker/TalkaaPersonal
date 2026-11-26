import SwiftUI
import SwiftData

/// 个性化答案定制（“说你自己的故事” + 语音转文字 + 多轮微调 + 存入我的答案库）
struct CustomAnswerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IELTSQuestion.questionCode) private var allQuestions: [IELTSQuestion]
    @Query(sort: \CustomAnswer.updatedAt, order: .reverse) private var savedAnswers: [CustomAnswer]

    let preselectedQuestion: IELTSQuestion?

    @State private var audioManager = AudioManager()
    @State private var selectedQuestion: IELTSQuestion?
    @State private var userStoryZh = ""
    @State private var targetBand: Double = 7.0
    @State private var styleMode = "自然口语化"
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @State private var currentAnswer: CustomAnswer?
    @State private var refinementInput = ""
    @State private var isRefining = false

    private let quickRefinements = [
        "再简短一点，控制在 1 分钟左右",
        "把第二段改得更自然口语化",
        "替换掉重复的简单词，升级到 Band 7.5 搭配",
        "加入一个更生动的真实情绪细节"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 选定题目与参数配置卡
                configCard

                // 2. 生成结果与多轮微调对话卡
                if let answer = currentAnswer {
                    generatedAnswerCard(answer)
                }

                // 3. 我的答案库归档列表
                if !savedAnswers.isEmpty {
                    savedAnswersSection
                }
            }
            .padding()
        }
        .onAppear {
            if selectedQuestion == nil {
                selectedQuestion = preselectedQuestion ?? allQuestions.first
            }
        }
        .onDisappear {
            audioManager.stopChineseDictation()
            audioManager.stopAllPlayback()
        }
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("说你自己的故事 · 告别千篇一律模板")
                .font(.headline)

            // 题目选择器
            Menu {
                ForEach(allQuestions) { q in
                    Button("[\(q.part.shortTitle)] \(q.topicTitle)") {
                        selectedQuestion = q
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前定制题目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedQuestion?.topicTitle ?? "请选择真题")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // 目标分与表达风格
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标分数").font(.caption).foregroundStyle(.secondary)
                    Picker("目标分数", selection: $targetBand) {
                        Text("6.0").tag(6.0)
                        Text("6.5").tag(6.5)
                        Text("7.0").tag(7.0)
                        Text("7.5+").tag(7.5)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Picker("表达风格", selection: $styleMode) {
                Text("自然口语化").tag("自然口语化")
                Text("正式学术风").tag("正式学术风")
            }
            .pickerStyle(.segmented)

            // 中文经历输入框 + 语音转文字按钮
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("输入你的中文碎片想法 / 真实经历")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if audioManager.isDictating {
                            audioManager.stopChineseDictation()
                        } else {
                            Task {
                                await audioManager.startChineseDictation { text in
                                    userStoryZh = text
                                }
                            }
                        }
                    } label: {
                        Label(audioManager.isDictating ? "停止听写" : "语音转文字",
                              systemImage: audioManager.isDictating ? "waveform.circle.fill" : "mic.badge.plus")
                            .font(.caption.bold())
                            .foregroundStyle(audioManager.isDictating ? .red : .indigo)
                    }
                }

                TextField("例如：大三那年我在杭州实习，带我的产品总监林姐帮我克服了当众汇报的恐惧...", text: $userStoryZh, axis: .vertical)
                    .lineLimit(4...7)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                generateAnswer()
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView().tint(.white)
                        Text("Gemini 4 Neon 正在定制专属答案...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    Label("生成专属高分答案", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(isGenerating || userStoryZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func generatedAnswerCard(_ answer: CustomAnswer) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("已自动存入「我的答案库」", systemImage: "checkmark.seal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    audioManager.speakEnglish(answer.answerEn)
                } label: {
                    Label("朗读跟读", systemImage: "speaker.wave.2.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

            Text(answer.answerEn)
                .font(.body)
                .lineSpacing(5)

            Divider()

            Text("中文对照")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(answer.answerZh)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !answer.highlights.isEmpty {
                Divider()
                Text("核心亮点词句解析")
                    .font(.caption.bold())
                    .foregroundStyle(.indigo)
                ForEach(answer.highlights) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.phrase).font(.subheadline.bold())
                        Text(item.meaningZh).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Divider()

            // 多轮微调面板
            VStack(alignment: .leading, spacing: 8) {
                Text("多轮对话微调")
                    .font(.subheadline.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickRefinements, id: \.self) { chip in
                            Button(chip) {
                                refinementInput = chip
                                refineAnswer(answer)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                        }
                    }
                }

                HStack {
                    TextField("输入微调要求（如：替换重复的 good）", text: $refinementInput)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        refineAnswer(answer)
                    } label: {
                        if isRefining {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                        }
                    }
                    .disabled(isRefining || refinementInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var savedAnswersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我的答案库 (\(savedAnswers.count))")
                .font(.headline)
            ForEach(savedAnswers) { item in
                Button {
                    currentAnswer = item
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.topicTitle)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Spacer()
                            Text("Band \(String(format: "%.1f", item.targetBand))")
                                .font(.caption2.bold())
                                .foregroundStyle(.indigo)
                        }
                        Text(item.answerEn)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func generateAnswer() {
        guard let q = selectedQuestion else { return }
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let dto = try await GeminiNeonService.shared.generateCustomAnswer(
                    part: q.part,
                    topicTitle: q.topicTitle,
                    promptText: q.promptText,
                    userStoryZh: userStoryZh,
                    targetBand: targetBand,
                    styleMode: styleMode
                )
                let created = CustomAnswer(
                    topicTitle: q.topicTitle,
                    userStoryZh: userStoryZh,
                    targetBand: targetBand,
                    styleMode: styleMode,
                    answerEn: dto.answerEn,
                    answerZh: dto.answerZh,
                    highlights: dto.highlights.map { VocabularyHighlightItem(phrase: $0.phrase, meaningZh: $0.explanationZh) },
                    coachNoteZh: dto.coachNoteZh,
                    question: q
                )
                modelContext.insert(created)
                try? modelContext.save()
                currentAnswer = created
                isGenerating = false
            } catch {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func refineAnswer(_ answer: CustomAnswer) {
        let instruction = refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        isRefining = true
        errorMessage = nil

        Task {
            do {
                let dto = try await GeminiNeonService.shared.refineCustomAnswer(
                    topicTitle: answer.topicTitle,
                    currentAnswerEn: answer.answerEn,
                    targetBand: answer.targetBand,
                    styleMode: answer.styleMode,
                    refinementInstruction: instruction
                )
                answer.answerEn = dto.answerEn
                answer.answerZh = dto.answerZh
                answer.highlights = dto.highlights.map { VocabularyHighlightItem(phrase: $0.phrase, meaningZh: $0.explanationZh) }
                answer.coachNoteZh = dto.coachNoteZh
                answer.updatedAt = Date()
                answer.refinementHistory.append(RefinementTurn(role: "user", message: instruction))
                try? modelContext.save()
                refinementInput = ""
                isRefining = false
            } catch {
                errorMessage = error.localizedDescription
                isRefining = false
            }
        }
    }
}
