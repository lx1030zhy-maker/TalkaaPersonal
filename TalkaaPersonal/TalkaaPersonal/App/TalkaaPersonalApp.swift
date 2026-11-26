import SwiftUI
import SwiftData

@main
struct TalkaaPersonalApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            IELTSQuestion.self,
            PracticeRecord.self,
            CustomAnswer.self,
            TopicClusterGroup.self,
            MockExamSessionRecord.self,
            StudyVaultItem.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            QuestionBankSeeder.seedIfNeeded(modelContext: modelContainer.mainContext)
        } catch {
            fatalError("SwiftData ModelContainer 初始化失败: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
