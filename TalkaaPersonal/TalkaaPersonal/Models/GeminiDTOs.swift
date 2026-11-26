import Foundation

// MARK: - 1. 音频四维评分 + 逐词时间戳纠音 JSON Schema DTO

struct IELTSScoringResponseDTO: Codable, Sendable {
    let overallBand: Double
    let criteria: CriteriaDTO
    let wordAnalysis: [WordAnalysisDTO]
    let band8SampleAnswer: String

    enum CodingKeys: String, CodingKey {
        case overallBand = "overall_band"
        case criteria
        case wordAnalysis = "word_analysis"
        case band8SampleAnswer = "band_8_sample_answer"
    }

    struct CriteriaDTO: Codable, Sendable {
        let fluencyCoherence: FluencyDTO
        let pronunciation: PronunciationDTO
        let lexicalResource: LexicalDTO
        let grammaticalRange: GrammarDTO

        enum CodingKeys: String, CodingKey {
            case fluencyCoherence = "fluency_coherence"
            case pronunciation
            case lexicalResource = "lexical_resource"
            case grammaticalRange = "grammatical_range"
        }
    }

    struct FluencyDTO: Codable, Sendable {
        let score: Double
        let wpm: Int
        let longPausesCount: Int
        let feedbackZh: String

        enum CodingKeys: String, CodingKey {
            case score, wpm
            case longPausesCount = "long_pauses_count"
            case feedbackZh = "feedback_zh"
        }
    }

    struct PronunciationDTO: Codable, Sendable {
        let score: Double
        let feedbackZh: String

        enum CodingKeys: String, CodingKey {
            case score
            case feedbackZh = "feedback_zh"
        }
    }

    struct LexicalDTO: Codable, Sendable {
        let score: Double
        let upgradedExpressions: [String]
        let feedbackZh: String

        enum CodingKeys: String, CodingKey {
            case score
            case upgradedExpressions = "upgraded_expressions"
            case feedbackZh = "feedback_zh"
        }
    }

    struct GrammarDTO: Codable, Sendable {
        let score: Double
        let grammarCorrections: [GrammarCorrectionDTO]
        let feedbackZh: String

        enum CodingKeys: String, CodingKey {
            case score
            case grammarCorrections = "grammar_corrections"
            case feedbackZh = "feedback_zh"
        }
    }

    struct GrammarCorrectionDTO: Codable, Sendable {
        let original: String
        let corrected: String
        let reasonZh: String

        enum CodingKeys: String, CodingKey {
            case original, corrected
            case reasonZh = "reason_zh"
        }
    }

    struct WordAnalysisDTO: Codable, Sendable {
        let word: String
        let startMs: Int
        let endMs: Int
        let status: String // "accurate" | "warning" | "error"
        let ipaTarget: String?
        let issueZh: String?

        enum CodingKeys: String, CodingKey {
            case word
            case startMs = "start_ms"
            case endMs = "end_ms"
            case status
            case ipaTarget = "ipa_target"
            case issueZh = "issue_zh"
        }
    }
}

// MARK: - 2. Part 2 智能串题与逐句 Diff JSON Schema DTO

struct Part2ClusteringResponseDTO: Codable, Sendable {
    let masterStory: MasterStoryDTO
    let adaptedTopics: [AdaptedTopicDTO]

    enum CodingKeys: String, CodingKey {
        case masterStory = "master_story"
        case adaptedTopics = "adapted_topics"
    }

    struct MasterStoryDTO: Codable, Sendable {
        let en: String
        let zh: String
        let keyVocabulary: [VocabDTO]

        enum CodingKeys: String, CodingKey {
            case en, zh
            case keyVocabulary = "key_vocabulary"
        }
    }

    struct VocabDTO: Codable, Sendable {
        let phrase: String
        let meaningZh: String

        enum CodingKeys: String, CodingKey {
            case phrase
            case meaningZh = "meaning_zh"
        }
    }

    struct AdaptedTopicDTO: Codable, Sendable {
        let topicId: String
        let topicTitle: String
        let sentences: [AdaptedSentenceDTO]

        enum CodingKeys: String, CodingKey {
            case topicId = "topic_id"
            case topicTitle = "topic_title"
            case sentences
        }
    }

    struct AdaptedSentenceDTO: Codable, Sendable {
        let en: String
        let zh: String
        let isAdapted: Bool

        enum CodingKeys: String, CodingKey {
            case en, zh
            case isAdapted = "is_adapted"
        }
    }
}

// MARK: - 3. 个性化答案定制 DTO

struct CustomAnswerResponseDTO: Codable, Sendable {
    let answerEn: String
    let answerZh: String
    let highlights: [HighlightDTO]
    let coachNoteZh: String

    enum CodingKeys: String, CodingKey {
        case answerEn = "answer_en"
        case answerZh = "answer_zh"
        case highlights
        case coachNoteZh = "coach_note_zh"
    }

    struct HighlightDTO: Codable, Sendable {
        let phrase: String
        let explanationZh: String

        enum CodingKeys: String, CodingKey {
            case phrase
            case explanationZh = "explanation_zh"
        }
    }
}

// MARK: - 4. Part 3 动态追问生成 DTO

struct Part3FollowUpResponseDTO: Codable, Sendable {
    let summaryOfPart2: String
    let questions: [String]

    enum CodingKeys: String, CodingKey {
        case summaryOfPart2 = "summary_of_part2"
        case questions
    }
}

// MARK: - 5. 外部 JSON 题库导入 DTO

struct ExternalQuestionBankFileDTO: Codable, Sendable {
    let season: String
    let questions: [ExternalQuestionDTO]

    struct ExternalQuestionDTO: Codable, Sendable {
        let id: String
        let part: Int
        let category: String
        let topicTitle: String
        let promptText: String
        let cueCardBullets: [String]?
        let subQuestions: [String]?
        let isHighFrequency: Bool?
        let targetBandTag: Double?
        let clusterGroupName: String?
    }
}
