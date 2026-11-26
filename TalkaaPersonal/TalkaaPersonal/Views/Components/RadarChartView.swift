import SwiftUI

/// 雅思四维能力雷达图（流利度、发音、词汇、语法）
struct RadarChartView: View {
    let fluency: Double
    let pronunciation: Double
    let lexical: Double
    let grammar: Double

    private let maxScore: Double = 9.0
    private let labels = ["流利度 FC", "发音 PR", "词汇 LR", "语法 GRA"]

    private var values: [Double] {
        [fluency, pronunciation, lexical, grammar]
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) * 0.34

            ZStack {
                // 背景网格（3 / 6 / 9 分三层菱形）
                ForEach([0.33, 0.66, 1.0], id: \.self) { scale in
                    polygonPath(center: center, radius: radius * scale, ratios: [1, 1, 1, 1])
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }

                // 坐标轴线
                ForEach(0..<4, id: \.self) { idx in
                    let pt = point(center: center, radius: radius, index: idx)
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: pt)
                    }
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                // 能力多边形填充
                let ratios = values.map { max(0.08, min(1.0, $0 / maxScore)) }
                polygonPath(center: center, radius: radius, ratios: ratios)
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.35), .blue.opacity(0.22)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                polygonPath(center: center, radius: radius, ratios: ratios)
                    .stroke(Color.indigo, lineWidth: 2.5)

                // 顶点圆点
                ForEach(0..<4, id: \.self) { idx in
                    let pt = point(center: center, radius: radius * ratios[idx], index: idx)
                    Circle()
                        .fill(Color.indigo)
                        .frame(width: 8, height: 8)
                        .position(pt)
                }

                // 维度标签与数值
                ForEach(0..<4, id: \.self) { idx in
                    let labelPt = point(center: center, radius: radius + 30, index: idx)
                    VStack(spacing: 2) {
                        Text(labels[idx])
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", values[idx]))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.indigo)
                    }
                    .position(labelPt)
                }
            }
        }
        .frame(height: 230)
    }

    private func angle(for index: Int) -> Double {
        return (Double(index) * .pi / 2.0) - (.pi / 2.0)
    }

    private func point(center: CGPoint, radius: CGFloat, index: Int) -> CGPoint {
        let a = angle(for: index)
        return CGPoint(
            x: center.x + cos(a) * radius,
            y: center.y + sin(a) * radius
        )
    }

    private func polygonPath(center: CGPoint, radius: CGFloat, ratios: [Double]) -> Path {
        Path { path in
            for i in 0..<4 {
                let pt = point(center: center, radius: radius * ratios[i], index: i)
                if i == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }
            path.closeSubpath()
        }
    }
}
