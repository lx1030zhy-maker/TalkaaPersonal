import SwiftUI

struct StoryStudioHubView: View {
    enum StudioTab: String, CaseIterable {
        case clustering = "Part 2 智能串题"
        case customAnswer = "个性化答案定制"
    }

    @State private var selectedTab: StudioTab = .clustering

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("功能模式", selection: $selectedTab) {
                    ForEach(StudioTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if selectedTab == .clustering {
                    TopicClusteringView()
                } else {
                    CustomAnswerView(preselectedQuestion: nil)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("串题与专属定制")
        }
    }
}
