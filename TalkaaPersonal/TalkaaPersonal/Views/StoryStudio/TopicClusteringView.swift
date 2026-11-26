import SwiftUI
import SwiftData

/// Part 2 智能串题（“一份素材，串起多道 Part 2” + 逐句 Diff 高亮对比 + Markdown/PDF 一键导出）
struct TopicClusteringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TopicClusterGroup.groupName) private var clusters: [TopicClusterGroup]
    @Query(sort: \IELTSQuestion.questionCode) private var allQuestions: [IELTSQuestion]

    @State private var selectedGroup: TopicClusterGroup?
    @State private var audioManager = AudioManager()
    @State private var isGenerating = false
    @State private var onlyHighlightDiff = false
    @State private var errorMessage: String?
    @State private var exportedMarkdownURL: URL?
    @State private var exportedPDFURL: URL?

    private func linkedPart2Questions(for group: TopicClusterGroup) -> [IELTSQuestion] {
        allQuestions.filter { $0.part == .part2 && $0.clusterGroupName == group.groupName }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 串题分组横向卡片选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clusters) { group in
                            let isSelected = selectedGroup?.id == group.id
                            Button {
                                selectedGroup = group
                                prepareExportFiles(for: group)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: group.iconName)
                                            .font(.title3)
                                        Spacer()
                                        Text("\(linkedPart2Questions(for: group).count) 题")
                                            .font(.caption2.bold())
                                    }
                                    Text(group.groupName)
                                        .font(.subheadline.bold())
                                    Text(group.masterStoryEn.isEmpty ? "待生成素材" : "已串联完成")
                                        .font(.caption2)
                                        .opacity(0.85)
                                }
                                .padding(14)
                                .frame(width: 158, alignment: .leading)
                                .background(isSelected ? Color.indigo : Color(.systemBackground))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let group = selectedGroup {
                    clusterEditorCard(group)

                    if !group.masterStoryEn.isEmpty {
                        masterStoryCard(group)
                        adaptedDiffSection(group)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if selectedGroup == nil, let first = clusters.first {
                selectedGroup = first
                prepareExportFiles(for: first)
            }
        }
        .onDisappear {
            audioManager.stopChineseDictation()
            audioManager.stopAllPlayback()
        }
    }

    private func clusterEditorCard(_ group: TopicClusterGroup) -> some View {
        let topics = linkedPart2Questions(for: group)
        return VStack(alignment: .leading, spacing: 12) {
            Text(group.groupDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            // 组内覆盖题目列表
            VStack(alignment: .leading, spacing: 6) {
                Text("本组串联覆盖的 Part 2 话题卡（\(topics.count) 道）")
                    .font(.caption.bold())
                    .foregroundStyle(.indigo)
                ForEach(topics) { q in
                    Label(q.topicTitle, systemImage: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 目标分数
            Picker("目标分数", selection: Binding(
                get: { group.targetBand },
                set: { group.targetBand = $0 }
            )) {
                Text("6.5").tag(6.5)
                Text("7.0").tag(7.0)
                Text("7.5").tag(7.5)
                Text("8.0").tag(8.0)
            }
            .pickerStyle(.segmented)

            // 一次输入中文个人经历
            HStack {
                Text("只需输入一次你的真实中文故事")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if audioManager.isDictating {
                        audioManager.stopChineseDictation()
                    } else {
                        Task {
                            await audioManager.startChineseDictation { text in
                                group.userStoryZh = text
                            }
                        }
                    }
                } label: {
                    Label(audioManager.isDictating ? "停止听写" : "语音输入", systemImage: "mic.fill")
                        .font(.caption.bold())
                        .foregroundStyle(audioManager.isDictating ? .red : .indigo)
                }
            }

            TextField("例如：去年国庆我和大学室友去京都自由行，我们在岚山遇到大雨但意外发现一家百年手冲咖啡馆...", text: Binding(
                get: { group.userStoryZh },
                set: { group.userStoryZh = $0 }
            ), axis: .vertical)
            .lineLimit(4...6)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                generateCluster(for: group, topics: topics)
            } label: {
                if isGenerating {
                    HStack {
                        ProgressView().tint(.white)
                        Text("正在生成万能素材与逐句 Diff...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    Label("一键生成万能素材 + 串联 \(topics.count) 道题", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(isGenerating || group.userStoryZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || topics.isEmpty)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func masterStoryCard(_ group: TopicClusterGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("核心万能素材 (Master Story)", systemImage: "star.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Spacer()
                Button {
                    audioManager.speakEnglish(group.masterStoryEn)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
            }

            Text(group.masterStoryEn)
                .font(.body)
                .lineSpacing(5)
            Text(group.masterStoryZh)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !group.keyVocabulary.isEmpty {
                Divider()
                Text("高频复用亮眼表达")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(group.keyVocabulary) { vocab in
                        Text("\(vocab.phrase) · \(vocab.meaningZh)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.12))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
            }

            // Markdown / PDF 一键导出分享
            HStack(spacing: 12) {
                if let mdURL = exportedMarkdownURL {
                    ShareLink(item: mdURL) {
                        Label("导出 Markdown", systemImage: "doc.plaintext")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                if let pdfURL = exportedPDFURL {
                    ShareLink(item: pdfURL) {
                        Label("导出 PDF 分享", systemImage: "doc.richtext")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func adaptedDiffSection(_ group: TopicClusterGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("逐句 Diff 高亮对比")
                    .font(.headline)
                Spacer()
                Toggle("仅看改写句", isOn: $onlyHighlightDiff)
                    .labelsHidden()
                Text("仅看改写句")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.28)).frame(width: 14, height: 14)
                    Text("适配改写句（仅需单独记）").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.12)).frame(width: 14, height: 14)
                    Text("直接复用原句（零额外记忆）").font(.caption2).foregroundStyle(.secondary)
                }
            }

            ForEach(group.adaptedTopics) { topic in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(topic.topicTitle)
                            .font(.subheadline.bold())
                        Spacer()
                        let adaptedCount = topic.sentences.filter(\.isAdapted).count
                        Text("仅改写 \(adaptedCount)/\(topic.sentences.count) 句")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.16))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    ForEach(topic.sentences.filter { !onlyHighlightDiff || $0.isAdapted }) { sentence in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(sentence.isAdapted ? "改写" : "复用")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(sentence.isAdapted ? Color.orange : Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(sentence.en)
                                    .font(.subheadline)
                            }
                            Text(sentence.zh)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 38)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sentence.isAdapted ? Color.orange.opacity(0.13) : Color.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func generateCluster(for group: TopicClusterGroup, topics: [IELTSQuestion]) {
        isGenerating = true
        errorMessage = nil

        let payloadTopics = topics.map { ($0.questionCode, $0.topicTitle, $0.cueCardBullets) }

        Task {
            do {
                let dto = try await GeminiNeonService.shared.generatePart2ClusterAdaptation(
                    userStoryZh: group.userStoryZh,
                    targetBand: group.targetBand,
                    topics: payloadTopics
                )
                group.masterStoryEn = dto.masterStory.en
                group.masterStoryZh = dto.masterStory.zh
                group.keyVocabulary = dto.masterStory.keyVocabulary.map {
                    VocabularyHighlightItem(phrase: $0.phrase, meaningZh: $0.meaningZh)
                }
                group.adaptedTopics = dto.adaptedTopics.map { topicDTO in
                    AdaptedTopicResultItem(
                        topicId: topicDTO.topicId,
                        topicTitle: topicDTO.topicTitle,
                        sentences: topicDTO.sentences.map {
                            AdaptedSentenceItem(en: $0.en, zh: $0.zh, isAdapted: $0.isAdapted)
                        }
                    )
                }
                group.updatedAt = Date()
                try? modelContext.save()
                prepareExportFiles(for: group)
                isGenerating = false
            } catch {
                errorMessage = error.localizedDescription
                isGenerating = false
            }
        }
    }

    private func prepareExportFiles(for group: TopicClusterGroup) {
        guard !group.masterStoryEn.isEmpty else {
            exportedMarkdownURL = nil
            exportedPDFURL = nil
            return
        }
        exportedMarkdownURL = try? ExportService.exportMarkdownFile(group: group)
        exportedPDFURL = try? ExportService.exportPDFFile(group: group)
    }
}
