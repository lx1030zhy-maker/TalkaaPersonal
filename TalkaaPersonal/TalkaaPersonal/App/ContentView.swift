import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            QuestionBankView()
                .tabItem {
                    Label("真题库", systemImage: "text.book.closed.fill")
                }

            MockExamView()
                .tabItem {
                    Label("全真模考", systemImage: "mic.badge.waveform")
                }

            StoryStudioHubView()
                .tabItem {
                    Label("串题与定制", systemImage: "sparkles.rectangle.stack.fill")
                }

            AnalyticsDashboardView()
                .tabItem {
                    Label("学习报告", systemImage: "chart.xyaxis.line")
                }
        }
        .tint(.indigo)
    }
}
