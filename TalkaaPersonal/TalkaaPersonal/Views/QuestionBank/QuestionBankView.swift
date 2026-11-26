import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct QuestionBankView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IELTSQuestion.questionCode) private var allQuestions: [IELTSQuestion]

    @State private var selectedPart: IELTSPart = .part1
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    @State private var onlyHighFrequency = false
    @State private var practiceFilter: PracticeStatusFilter = .all
    @State private var minTargetBand: Double = 6.0

    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var showingVault = false
    @State private var importAlertMessage: String?

    enum PracticeStatusFilter: String, CaseIterable {
        case all = "全部"
        case unpracticed = "未练"
        case practiced = "已练"
    }

    private var categoriesForCurrentPart: [String] {
        let cats = Set(allQuestions.filter { $0.part == selectedPart }.map(\.category))
        return ["全部"] + cats.sorted()
    }

    private var filteredQuestions: [IELTSQuestion] {
        allQuestions.filter { q in
            guard q.part == selectedPart else { return false }
            if selectedCategory != "全部" && q.category != selectedCategory { return false }
            if onlyHighFrequency && !q.isHighFrequency { return false }
            if practiceFilter == .practiced && !q.isPracticed { return false }
            if practiceFilter == .unpracticed && q.isPracticed { return false }
            if q.targetBandTag < minTargetBand { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return q.topicTitle.lowercased().contains(query)
                    || q.promptText.lowercased().contains(query)
                    || q.category.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Part 1 / 2 / 3 分段器
                Picker("考试部分", selection: $selectedPart) {
                    ForEach(IELTSPart.allCases) { part in
                        Text(part.shortTitle).tag(part)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: selectedPart) { _, _ in
                    selectedCategory = "全部"
                }

                // 多维筛选条
                filterBar

                // 题目列表
                List {
                    if filteredQuestions.isEmpty {
                        ContentUnavailableView(
                            "暂无匹配题目",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("请调整筛选条件，或点击右上角导入当季外部 JSON 题库。")
                        )
                    } else {
                        ForEach(filteredQuestions) { question in
                            NavigationLink(destination: PracticeSessionView(question: question)) {
                                QuestionRowCard(question: question)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("当季雅思真题库")
            .searchable(text: $searchText, prompt: "搜索话题、分类或关键词")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingVault = true
                    } label: {
                        Label("素材库", systemImage: "books.vertical")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("导入外部 JSON 题库包")

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        do {
                            let count = try QuestionBankSeeder.importExternalJSON(from: url, modelContext: modelContext)
                            importAlertMessage = "成功导入 \(count) 道新题目到本地 SwiftData 题库！"
                        } catch {
                            importAlertMessage = "JSON 题库导入失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    importAlertMessage = "文件选择失败：\(error.localizedDescription)"
                }
            }
            .alert("题库导入", isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(importAlertMessage ?? "")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingVault) {
                NavigationStack {
                    StudyVaultView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") { showingVault = false }
                            }
                        }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 高频开关
                Button {
                    withAnimation { onlyHighFrequency.toggle() }
                } label: {
                    Label("本月高频", systemImage: "flame.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(onlyHighFrequency ? Color.orange : Color(.secondarySystemBackground))
                        .foregroundStyle(onlyHighFrequency ? .white : .primary)
                        .clipShape(Capsule())
                }

                // 练习状态菜单
                Menu {
                    ForEach(PracticeStatusFilter.allCases, id: \.self) { state in
                        Button(state.rawValue) { practiceFilter = state }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("状态：\(practiceFilter.rawValue)")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }

                // 目标分筛选
                Menu {
                    ForEach([6.0, 6.5, 7.0, 7.5], id: \.self) { band in
                        Button("目标 ≥ \(String(format: "%.1f", band))") { minTargetBand = band }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("目标 ≥ \(String(format: "%.1f", minTargetBand))")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }

                // 分类标签
                ForEach(categoriesForCurrentPart, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        Text(cat)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedCategory == cat ? Color.indigo : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
}

private struct QuestionRowCard: View {
    let question: IELTSQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(question.category)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.12))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())

                if question.isHighFrequency {
                    Label("高频", systemImage: "flame.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }

                Text("目标 \(String(format: "%.1f", question.targetBandTag))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let score = question.latestScore {
                    Text(String(format: "Band %.1f", score))
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.16))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else {
                    Text("未练习")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(question.topicTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(question.promptText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !question.clusterGroupName.isEmpty {
                Label("可串题分组：\(question.clusterGroupName)", systemImage: "sparkles.rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
