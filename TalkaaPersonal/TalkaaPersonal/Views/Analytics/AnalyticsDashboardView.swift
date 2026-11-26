import SwiftUI
import SwiftData
import Charts

/// 可视化学习报告看板（Swift Charts 折线趋势图 + 四维雷达图 + 弱项自动诊断）
struct AnalyticsDashboardView: View {
    @Query(sort: \PracticeRecord.createdAt) private var practiceRecords: [PracticeRecord]
    @Query(sort: \MockExamSessionRecord.createdAt) private var mockRecords: [MockExamSessionRecord]
    @Query private var vaultItems: [StudyVaultItem]

    @State private var showingSettings = false

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Double
        let source: String
    }

    private var trendPoints: [TrendPoint] {
        let p = practiceRecords.map { TrendPoint(date: $0.createdAt, score: $0.overallBand, source: "单题练习") }
        let m = mockRecords.map { TrendPoint(date: $0.createdAt, score: $0.overallBand, source: "全真模考") }
        return (p + m).sorted { $0.date < $1.date }
    }

    private var totalMinutes: Int {
        let pSec = practiceRecords.reduce(0) { $0 + $1.durationSeconds }
        let mSec = mockRecords.reduce(0) { $0 + $1.totalDurationSeconds }
        return Int((pSec + mSec) / 60.0)
    }

    private var avgFluency: Double { averageDimension(\.fluencyScore, mockKeyPath: \.fluencyScore) }
    private var avgPronunciation: Double { averageDimension(\.pronunciationScore, mockKeyPath: \.pronunciationScore) }
    private var avgLexical: Double { averageDimension(\.lexicalScore, mockKeyPath: \.lexicalScore) }
    private var avgGrammar: Double { averageDimension(\.grammarScore, mockKeyPath: \.grammarScore) }

    private var overallAverage: Double {
        guard !trendPoints.isEmpty else { return 0 }
        return trendPoints.map(\.score).reduce(0, +) / Double(trendPoints.count)
    }

    private var weakestDimensionAdvice: (name: String, score: Double, suggestion: String) {
        let dims: [(String, Double, String)] = [
            ("流利度与连贯性 (FC)", avgFluency, "建议每日进行 2 组 Part 2 计时脱稿复述，控制语速在 120–150 WPM，用自然过渡短语替换 um/uh 停顿。"),
            ("发音表现 (PR)", avgPronunciation, "建议优先复盘报告中标红的音素词，利用「点词回放 + 单句跟读重练」集中攻克重音错位与尾音吞音。"),
            ("词汇多样性 (LR)", avgLexical, "建议前往「提分素材库」背诵高频地道搭配，并在定制答案时主动要求替换 good/very 等高频基础词。"),
            ("语法广度与准确性 (GRA)", avgGrammar, "建议在 Part 2 叙事中刻意保持一般过去时一致性，并在 Part 3 中每题至少使用 1 句让步/条件复合句。")
        ]
        return dims.min(by: { $0.1 < $1.1 }) ?? dims[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. 顶部核心指标卡
                    HStack(spacing: 12) {
                        StatTile(title: "累计开口", value: "\(totalMinutes) 分钟", icon: "clock.fill", tint: .indigo)
                        StatTile(title: "已完成题数", value: "\(practiceRecords.count + mockRecords.count)", icon: "checkmark.circle.fill", tint: .green)
                        StatTile(title: "均分预估", value: overallAverage > 0 ? String(format: "%.1f", overallAverage) : "--", icon: "chart.line.uptrend.xyaxis", tint: .orange)
                    }

                    // 2. 四维能力雷达图
                    VStack(alignment: .leading, spacing: 8) {
                        Text("雅思四维能力雷达图")
                            .font(.headline)
                        if trendPoints.isEmpty {
                            Text("完成任意一次练习或模考后，将在此绘制您的实时四维雷达图。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        } else {
                            RadarChartView(
                                fluency: avgFluency,
                                pronunciation: avgPronunciation,
                                lexical: avgLexical,
                                grammar: avgGrammar
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // 3. 历史总分折线趋势图 (Swift Charts)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("历史总分走势 (Swift Charts)")
                            .font(.headline)
                        if trendPoints.isEmpty {
                            Text("暂无评分趋势数据。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            Chart(trendPoints) { pt in
                                AreaMark(
                                    x: .value("日期", pt.date),
                                    yStart: .value("基线", 4.0),
                                    yEnd: .value("分数", pt.score)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.indigo.opacity(0.28), .indigo.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("日期", pt.date),
                                    y: .value("分数", pt.score)
                                )
                                .foregroundStyle(.indigo)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))

                                PointMark(
                                    x: .value("日期", pt.date),
                                    y: .value("分数", pt.score)
                                )
                                .foregroundStyle(pt.source == "全真模考" ? .orange : .indigo)
                            }
                            .chartYScale(domain: 4.0...9.0)
                            .frame(height: 200)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // 4. 自动弱项识别与针对性训练建议
                    if !trendPoints.isEmpty {
                        let weakest = weakestDimensionAdvice
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("AI 弱项定位与提分处方", systemImage: "target")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                Spacer()
                                Text("当前短板：\(String(format: "%.1f", weakest.score))")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.12))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                            Text(weakest.name)
                                .font(.subheadline.bold())
                            Text(weakest.suggestion)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    // 5. 提分素材库入口卡
                    NavigationLink(destination: StudyVaultView()) {
                        HStack {
                            Image(systemName: "books.vertical.fill")
                                .font(.title2)
                                .foregroundStyle(.purple)
                                .frame(width: 44, height: 44)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("提分素材库 (Study Vault)")
                                    .font(.headline)
                                Text("已收录 \(vaultItems.count) 条高分连接词、习语、框架与个人收藏")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("学习报告")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private func averageDimension(
        _ practiceKeyPath: KeyPath<PracticeRecord, Double>,
        mockKeyPath: KeyPath<MockExamSessionRecord, Double>
    ) -> Double {
        let pVals = practiceRecords.map { $0[keyPath: practiceKeyPath] }
        let mVals = mockRecords.map { $0[keyPath: mockKeyPath] }
        let all = pVals + mVals
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / Double(all.count)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
