import SwiftUI
import SwiftData

/// 提分素材库（高频连接词、地道习语、万金油框架、用户收藏高分表达）
struct StudyVaultView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyVaultItem.createdAt, order: .reverse) private var items: [StudyVaultItem]

    @State private var selectedCategory = "全部"
    @State private var searchText = ""
    @State private var audioManager = AudioManager()
    @State private var showingAddSheet = false

    private let categories = ["全部", "高频连接词", "地道习语", "万金油框架", "我的收藏"]

    private var filteredItems: [StudyVaultItem] {
        items.filter { item in
            if selectedCategory == "我的收藏" {
                guard item.isFavorite || item.category == "我的收藏" else { return false }
            } else if selectedCategory != "全部" {
                guard item.category == selectedCategory else { return false }
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.titleEn.lowercased().contains(q) || item.meaningZh.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button(cat) {
                            selectedCategory = cat
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedCategory == cat ? Color.indigo : Color(.secondarySystemBackground))
                        .foregroundStyle(selectedCategory == cat ? .white : .primary)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            List {
                ForEach(filteredItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.category)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())

                            Text(item.partScope)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                audioManager.speakEnglish(item.exampleEn.isEmpty ? item.titleEn : item.exampleEn)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)

                            Button {
                                item.isFavorite.toggle()
                                try? modelContext.save()
                            } label: {
                                Image(systemName: item.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(item.titleEn)
                            .font(.headline)
                        Text(item.meaningZh)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !item.exampleEn.isEmpty {
                            Text("例句：\(item.exampleEn)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    for idx in offsets {
                        modelContext.delete(filteredItems[idx])
                    }
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle("提分素材库")
        .searchable(text: $searchText, prompt: "搜索习语、连接词或例句")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddVaultItemSheet()
        }
    }
}

private struct AddVaultItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var category = "我的收藏"
    @State private var partScope = "通用"
    @State private var titleEn = ""
    @State private var meaningZh = ""
    @State private var exampleEn = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("分类", selection: $category) {
                    Text("我的收藏").tag("我的收藏")
                    Text("高频连接词").tag("高频连接词")
                    Text("地道习语").tag("地道习语")
                    Text("万金油框架").tag("万金油框架")
                }
                Picker("适用部分", selection: $partScope) {
                    Text("通用").tag("通用")
                    Text("Part 1").tag("Part 1")
                    Text("Part 2").tag("Part 2")
                    Text("Part 3").tag("Part 3")
                }
                TextField("英文表达 / 框架名称", text: $titleEn)
                TextField("中文释义与使用场景", text: $meaningZh)
                TextField("高分英文例句", text: $exampleEn, axis: .vertical)
                    .lineLimit(3...5)
            }
            .navigationTitle("新增提分素材")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let item = StudyVaultItem(
                            category: category,
                            partScope: partScope,
                            titleEn: titleEn,
                            meaningZh: meaningZh,
                            exampleEn: exampleEn,
                            isFavorite: true
                        )
                        modelContext.insert(item)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(titleEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
