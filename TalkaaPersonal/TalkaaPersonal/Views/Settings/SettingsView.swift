import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 个人无后端配置页：Keychain 安全存储 Gemini API Key、模型配置、考官口音与 JSON 题库导入
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var statusMessage: String?
    @State private var showingImporter = false

    @AppStorage("gemini_model_name") private var modelName = "gemini-4-neon"
    @AppStorage("examiner_accent") private var examinerAccent = "en-GB"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: hasStoredKey ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(hasStoredKey ? .green : .orange)
                        Text(hasStoredKey ? "API Key 已加密存于 iOS Keychain" : "尚未配置 Google AI Studio API Key")
                            .font(.subheadline)
                    }

                    SecureField("粘贴 Google AI Studio API Key (AIza...)", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Button("安全保存到 Keychain") {
                            saveKey()
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Spacer()

                        if hasStoredKey {
                            Button("清除 Key", role: .destructive) {
                                KeychainManager.shared.deleteAPIKey()
                                hasStoredKey = false
                                statusMessage = "已从本机 Keychain 删除 API Key。"
                            }
                        }
                    }
                } header: {
                    Text("Gemini 4 Neon 直连鉴权（无后端架构）")
                } footer: {
                    Text("您的 API Key 仅加密保存在本机 iOS Keychain，录音与评分请求直接发送至 Google Gemini API，不经过任何第三方中转服务器。")
                }

                Section("模型与考官语音设置") {
                    HStack {
                        Text("模型标识")
                        Spacer()
                        TextField("gemini-4-neon", text: $modelName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.indigo)
                    }

                    Picker("AI 考官朗读口音", selection: $examinerAccent) {
                        Text("英式英语 (en-GB · 推荐)").tag("en-GB")
                        Text("美式英语 (en-US)").tag("en-US")
                        Text("澳式英语 (en-AU)").tag("en-AU")
                    }
                }

                Section("题库管理") {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("导入外部当季雅思真题 JSON 包", systemImage: "square.and.arrow.down")
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                hasStoredKey = (KeychainManager.shared.loadAPIKey() != nil)
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
                            statusMessage = "成功导入 \(count) 道当季新题！"
                        } catch {
                            statusMessage = "导入失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    statusMessage = "文件选择取消或失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func saveKey() {
        do {
            try KeychainManager.shared.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            hasStoredKey = true
            statusMessage = "API Key 已安全加密存入 iOS Keychain！"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
