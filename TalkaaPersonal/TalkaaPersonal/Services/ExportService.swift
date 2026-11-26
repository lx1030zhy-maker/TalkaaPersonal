import Foundation
import UIKit

/// 将 Part 2 智能串题结果导出为 Markdown 或 PDF 文件，供 iOS ShareLink 一键分享
enum ExportService {
    static func buildClusterMarkdown(group: TopicClusterGroup) -> String {
        var md = "# Part 2 智能串题笔记：\(group.groupName)\n\n"
        md += "- **目标分数**: Band \(String(format: "%.1f", group.targetBand))\n"
        md += "- **个人背景故事**: \(group.userStoryZh)\n\n"
        md += "## 一、核心万能素材 (Master Story)\n\n"
        md += "\(group.masterStoryEn)\n\n"
        md += "> 中文对照：\(group.masterStoryZh)\n\n"

        if !group.keyVocabulary.isEmpty {
            md += "### 核心提分表达\n"
            for vocab in group.keyVocabulary {
                md += "- **\(vocab.phrase)**：\(vocab.meaningZh)\n"
            }
            md += "\n"
        }

        md += "## 二、串联适配题目（逐句 Diff 标记）\n\n"
        for (idx, topic) in group.adaptedTopics.enumerated() {
            md += "### \(idx + 1). \(topic.topicTitle)\n\n"
            for sentence in topic.sentences {
                let tag = sentence.isAdapted ? "[适配改写]" : "[直接复用]"
                md += "- **\(tag)** \(sentence.en)\n  - _\(sentence.zh)_\n"
            }
            md += "\n"
        }
        return md
    }

    static func exportMarkdownFile(group: TopicClusterGroup) throws -> URL {
        let content = buildClusterMarkdown(group: group)
        let safeName = group.groupName.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Talkaa_串题_\(safeName).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func exportPDFFile(group: TopicClusterGroup) throws -> URL {
        let safeName = group.groupName.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Talkaa_串题_\(safeName).pdf")

        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let margin: CGFloat = 40
        let contentWidth = pageBounds.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        let text = buildClusterMarkdown(group: group)
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "**", with: "")

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        try renderer.writePDF(to: url) { context in
            var currentRange = CFRange(location: 0, length: 0)
            while currentRange.location < attributed.length {
                context.beginPage()
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageBounds.height)
                cgContext.scaleBy(x: 1.0, y: -1.0)

                let path = CGPath(
                    rect: CGRect(x: margin, y: margin, width: contentWidth, height: pageBounds.height - margin * 2),
                    transform: nil
                )
                let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 { break }
                currentRange.location += visibleRange.length
                currentRange.length = 0
            }
        }
        return url
    }
}
