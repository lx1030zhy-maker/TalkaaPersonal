import Foundation
import SwiftData

// MARK: - 枚举与值类型（支持 SwiftData 自动编码存储）

enum IELTSPart: Int, Codable, CaseIterable, Identifiable, Sendable {
    case part1 = 1
    case part2 = 2
    case part3 = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .part1: return "Part 1 日常问答"
        case .part2: return "Part 2 话题卡"
        case .part3: return "Part 3 深度讨论"
        }
    }

    var shortTitle: String { "Part \(rawValue)" }
}

enum PronunciationStatus: String, Codable, Sendable {
    case accurate
    case warning
    case error

    init(rawStatus: String) {
        switch rawStatus.lowercased() {
        case "error", "red", "bad":
            self = .error
        case "warning", "yellow", "fair":
            self = .warning
        default:
            self = .accurate
        }
    }
}

struct WordAnalysisItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var word: String
    var startMs: Int
    var endMs: Int
    var status: PronunciationStatus
    var ipaTarget: String
    var issueZh: String

    init(
        id: UUID = UUID(),
        word: String,
        startMs: Int,
        endMs: Int,
        status: PronunciationStatus,
        ipaTarget: String = "",
        issueZh: String = ""
    ) {
        self.id = id
        self.word = word
        self.startMs = startMs
        self.endMs = endMs
        self.status = status
        self.ipaTarget = ipaTarget
        self.issueZh = issueZh
    }
}

struct GrammarCorrectionItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var original: String
    var corrected: String
    var reasonZh: String
}

struct VocabularyHighlightItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var phrase: String
    var meaningZh: String
}

struct AdaptedSentenceItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var en: String
    var zh: String
    var isAdapted: Bool
}

struct AdaptedTopicResultItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var topicId: String
    var topicTitle: String
    var sentences: [AdaptedSentenceItem]
}

struct RefinementTurn: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var role: String // "user" | "assistant"
    var message: String
    var timestamp: Date = Date()
}

// MARK: - 1. 雅思口语真题模型

@Model
final class IELTSQuestion {
    @Attribute(.unique) var questionCode: String
    var partRaw: Int
    var category: String
    var topicTitle: String
    var promptText: String
    var cueCardBullets: [String]
    var subQuestions: [String]
    var isHighFrequency: Bool
    var targetBandTag: Double
    var isPracticed: Bool
    var clusterGroupName: String
    var seasonTag: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PracticeRecord.question)
    var practiceRecords: [PracticeRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \CustomAnswer.question)
    var customAnswers: [CustomAnswer] = []

    var part: IELTSPart {
        get { IELTSPart(rawValue: partRaw) ?? .part1 }
        set { partRaw = newValue.rawValue }
    }

    var latestScore: Double? {
        practiceRecords.sorted(by: { $0.createdAt > $1.createdAt }).first?.overallBand
    }

    init(
        questionCode: String,
        part: IELTSPart,
        category: String,
        topicTitle: String,
        promptText: String,
        cueCardBullets: [String] = [],
        subQuestions: [String] = [],
        isHighFrequency: Bool = false,
        targetBandTag: Double = 7.0,
        isPracticed: Bool = false,
        clusterGroupName: String = "",
        seasonTag: String = "2026 Q4 当季题库"
    ) {
        self.questionCode = questionCode
        self.partRaw = part.rawValue
        self.category = category
        self.topicTitle = topicTitle
        self.promptText = promptText
        self.cueCardBullets = cueCardBullets
        self.subQuestions = subQuestions
        self.isHighFrequency = isHighFrequency
        self.targetBandTag = targetBandTag
        self.isPracticed = isPracticed
        self.clusterGroupName = clusterGroupName
        self.seasonTag = seasonTag
        self.createdAt = Date()
    }
}

// MARK: - 2. 练习录音与四维评分记录模型

@Model
final class PracticeRecord {
    var id: UUID
    var createdAt: Date
    var audioFileName: String
    var durationSeconds: Double
    var promptSnapshot: String
    var partRaw: Int

    // 四维总分与细分
    var overallBand: Double
    var fluencyScore: Double
    var pronunciationScore: Double
    var lexicalScore: Double
    var grammarScore: Double

    // 语速与停顿指标
    var wpm: Int
    var longPausesCount: Int

    // 中文点评
    var fluencyFeedbackZh: String
    var pronunciationFeedbackZh: String
    var lexicalFeedbackZh: String
    var grammarFeedbackZh: String

    // 提分建议与纠错详情
    var upgradedExpressions: [String]
    var grammarCorrections: [GrammarCorrectionItem]
    var wordAnalysis: [WordAnalysisItem]
    var band8SampleAnswer: String

    var question: IELTSQuestion?

    var part: IELTSPart {
        IELTSPart(rawValue: partRaw) ?? .part1
    }

    var audioFileURL: URL? {
        guard !audioFileName.isEmpty else { return nil }
        return AudioStorageHelper.recordingsDirectory.appendingPathComponent(audioFileName)
    }

    init(
        audioFileName: String,
        durationSeconds: Double,
        promptSnapshot: String,
        part: IELTSPart,
        dto: IELTSScoringResponseDTO,
        question: IELTSQuestion? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.audioFileName = audioFileName
        self.durationSeconds = durationSeconds
        self.promptSnapshot = promptSnapshot
        self.partRaw = part.rawValue
        self.overallBand = dto.overallBand
        self.fluencyScore = dto.criteria.fluencyCoherence.score
        self.pronunciationScore = dto.criteria.pronunciation.score
        self.lexicalScore = dto.criteria.lexicalResource.score
        self.grammarScore = dto.criteria.grammaticalRange.score
        self.wpm = dto.criteria.fluencyCoherence.wpm
        self.longPausesCount = dto.criteria.fluencyCoherence.longPausesCount
        self.fluencyFeedbackZh = dto.criteria.fluencyCoherence.feedbackZh
        self.pronunciationFeedbackZh = dto.criteria.pronunciation.feedbackZh
        self.lexicalFeedbackZh = dto.criteria.lexicalResource.feedbackZh
        self.grammarFeedbackZh = dto.criteria.grammaticalRange.feedbackZh
        self.upgradedExpressions = dto.criteria.lexicalResource.upgradedExpressions
        self.grammarCorrections = dto.criteria.grammaticalRange.grammarCorrections.map {
            GrammarCorrectionItem(original: $0.original, corrected: $0.corrected, reasonZh: $0.reasonZh)
        }
        self.wordAnalysis = dto.wordAnalysis.map {
            WordAnalysisItem(
                word: $0.word,
                startMs: $0.startMs,
                endMs: $0.endMs,
                status: PronunciationStatus(rawStatus: $0.status),
                ipaTarget: $0.ipaTarget ?? "",
                issueZh: $0.issueZh ?? ""
            )
        }
        self.band8SampleAnswer = dto.band8SampleAnswer
        self.question = question
    }
}

// MARK: - 3. 个性化定制答案模型 (“说你自己的故事”)

@Model
final class CustomAnswer {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var topicTitle: String
    var userStoryZh: String
    var targetBand: Double
    var styleMode: String // "自然口语化" | "正式学术风"
    var answerEn: String
    var answerZh: String
    var highlights: [VocabularyHighlightItem]
    var coachNoteZh: String
    var refinementHistory: [RefinementTurn]
    var isSavedToVault: Bool

    var question: IELTSQuestion?

    init(
        topicTitle: String,
        userStoryZh: String,
        targetBand: Double,
        styleMode: String,
        answerEn: String,
        answerZh: String,
        highlights: [VocabularyHighlightItem],
        coachNoteZh: String,
        question: IELTSQuestion? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.topicTitle = topicTitle
        self.userStoryZh = userStoryZh
        self.targetBand = targetBand
        self.styleMode = styleMode
        self.answerEn = answerEn
        self.answerZh = answerZh
        self.highlights = highlights
        self.coachNoteZh = coachNoteZh
        self.refinementHistory = []
        self.isSavedToVault = true
        self.question = question
    }
}

// MARK: - 4. Part 2 智能串题分组模型

@Model
final class TopicClusterGroup {
    var id: UUID
    var groupName: String
    var groupDescription: String
    var iconName: String
    var userStoryZh: String
    var targetBand: Double
    var masterStoryEn: String
    var masterStoryZh: String
    var keyVocabulary: [VocabularyHighlightItem]
    var adaptedTopics: [AdaptedTopicResultItem]
    var updatedAt: Date

    init(
        groupName: String,
        groupDescription: String,
        iconName: String = "sparkles.rectangle.stack",
        userStoryZh: String = "",
        targetBand: Double = 7.0
    ) {
        self.id = UUID()
        self.groupName = groupName
        self.groupDescription = groupDescription
        self.iconName = iconName
        self.userStoryZh = userStoryZh
        self.targetBand = targetBand
        self.masterStoryEn = ""
        self.masterStoryZh = ""
        self.keyVocabulary = []
        self.adaptedTopics = []
        self.updatedAt = Date()
    }
}

// MARK: - 5. 全真模考归档记录模型

@Model
final class MockExamSessionRecord {
    var id: UUID
    var createdAt: Date
    var totalDurationSeconds: Double
    var part1TopicsSummary: String
    var part2TopicTitle: String
    var part2Notes: String
    var part3Questions: [String]
    var audioFileNames: [String]

    var overallBand: Double
    var fluencyScore: Double
    var pronunciationScore: Double
    var lexicalScore: Double
    var grammarScore: Double
    var wpm: Int
    var longPausesCount: Int

    var fluencyFeedbackZh: String
    var pronunciationFeedbackZh: String
    var lexicalFeedbackZh: String
    var grammarFeedbackZh: String
    var upgradedExpressions: [String]
    var grammarCorrections: [GrammarCorrectionItem]
    var wordAnalysis: [WordAnalysisItem]
    var band8SampleAnswer: String

    init(
        totalDurationSeconds: Double,
        part1TopicsSummary: String,
        part2TopicTitle: String,
        part2Notes: String,
        part3Questions: [String],
        audioFileNames: [String],
        dto: IELTSScoringResponseDTO
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.totalDurationSeconds = totalDurationSeconds
        self.part1TopicsSummary = part1TopicsSummary
        self.part2TopicTitle = part2TopicTitle
        self.part2Notes = part2Notes
        self.part3Questions = part3Questions
        self.audioFileNames = audioFileNames
        self.overallBand = dto.overallBand
        self.fluencyScore = dto.criteria.fluencyCoherence.score
        self.pronunciationScore = dto.criteria.pronunciation.score
        self.lexicalScore = dto.criteria.lexicalResource.score
        self.grammarScore = dto.criteria.grammaticalRange.score
        self.wpm = dto.criteria.fluencyCoherence.wpm
        self.longPausesCount = dto.criteria.fluencyCoherence.longPausesCount
        self.fluencyFeedbackZh = dto.criteria.fluencyCoherence.feedbackZh
        self.pronunciationFeedbackZh = dto.criteria.pronunciation.feedbackZh
        self.lexicalFeedbackZh = dto.criteria.lexicalResource.feedbackZh
        self.grammarFeedbackZh = dto.criteria.grammaticalRange.feedbackZh
        self.upgradedExpressions = dto.criteria.lexicalResource.upgradedExpressions
        self.grammarCorrections = dto.criteria.grammaticalRange.grammarCorrections.map {
            GrammarCorrectionItem(original: $0.original, corrected: $0.corrected, reasonZh: $0.reasonZh)
        }
        self.wordAnalysis = dto.wordAnalysis.map {
            WordAnalysisItem(
                word: $0.word,
                startMs: $0.startMs,
                endMs: $0.endMs,
                status: PronunciationStatus(rawStatus: $0.status),
                ipaTarget: $0.ipaTarget ?? "",
                issueZh: $0.issueZh ?? ""
            )
        }
        self.band8SampleAnswer = dto.band8SampleAnswer
    }
}

// MARK: - 6. 提分素材库模型 (Study Vault)

@Model
final class StudyVaultItem {
    var id: UUID
    var category: String // "高频连接词" | "地道习语" | "万金油框架" | "我的收藏"
    var partScope: String // "Part 1" | "Part 2" | "Part 3" | "通用"
    var titleEn: String
    var meaningZh: String
    var exampleEn: String
    var isFavorite: Bool
    var createdAt: Date

    init(
        category: String,
        partScope: String,
        titleEn: String,
        meaningZh: String,
        exampleEn: String,
        isFavorite: Bool = false
    ) {
        self.id = UUID()
        self.category = category
        self.partScope = partScope
        self.titleEn = titleEn
        self.meaningZh = meaningZh
        self.exampleEn = exampleEn
        self.isFavorite = isFavorite
        self.createdAt = Date()
    }
}

// MARK: - 本地音频目录工具

enum AudioStorageHelper {
    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
