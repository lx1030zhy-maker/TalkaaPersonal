import Foundation

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case audioFileReadFailed
    case fileUploadFailed(String)
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    case decodingFailed(rawText: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 Google AI Studio API Key，请前往「设置」页安全存入 Keychain。"
        case .invalidURL:
            return "Gemini API 接口地址无效。"
        case .audioFileReadFailed:
            return "无法读取本地 .m4a 录音文件。"
        case .fileUploadFailed(let detail):
            return "Gemini File API 上传音频失败：\(detail)"
        case .httpError(let code, let message):
            return "Gemini API 请求失败 (HTTP \(code))：\(message)"
        case .emptyResponse:
            return "模型未返回有效文本内容。"
        case .decodingFailed(_, let underlying):
            return "结构化 JSON 解析失败：\(underlying.localizedDescription)"
        }
    }
}

/// 负责直连 Google Gemini 4 Neon 多模态 API 的无服务器网络层
actor GeminiNeonService {
    static let shared = GeminiNeonService()

    private let baseURL = "https://generativelanguage.googleapis.com"
    private let inlineDataThresholdBytes = 15 * 1024 * 1024 // 15 MB 阈值，超过自动切换 File API

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private var modelName: String {
        let saved = UserDefaults.standard.string(forKey: "gemini_model_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (saved?.isEmpty == false) ? saved! : "gemini-4-neon"
    }

    // MARK: - 嵌入 App 内部的核心 System Prompts（严格对齐业务规范）

    /// 1. 音频四维评分 + 逐词时间戳纠音 System Prompt
    static let ieltsScoringSystemPrompt = """
    你是一位拥有 15 年经验的雅思口语官方前考官与语音学专家。
    你将直接聆听考生的英文作答音频，并结合题目给出严格对齐雅思官方评分标准的诊断报告。

    【任务要求】
    1. 仔细聆听音频中的真实发音、重音、语调、停顿与流利度，切勿仅依赖文本语义评分。
    2. 逐词转录考生的实际发音内容（包含重复、自我纠正或填充词），并为每个单词标注音频中的起止毫秒时间戳（start_ms, end_ms）。
    3. 针对发音存在明显音素偏差（如 th/r/l/v/w 混淆、元音不饱满）或重音错位的单词，标记 status 为 "error" 或 "warning"，并给出正确的 IPA 音标、错误原因及中文发音纠正建议；发音准确的单词标记为 "accurate"。
    4. 严格按照以下 JSON Schema 输出，不要包含任何 Markdown 代码块标记或额外解释文本：

    {
      "overall_band": 6.5,
      "criteria": {
        "fluency_coherence": { "score": 6.5, "wpm": 132, "long_pauses_count": 2, "feedback_zh": "..." },
        "pronunciation": { "score": 6.0, "feedback_zh": "..." },
        "lexical_resource": { "score": 6.5, "upgraded_expressions": ["..."], "feedback_zh": "..." },
        "grammatical_range": { "score": 6.5, "grammar_corrections": [{ "original": "...", "corrected": "...", "reason_zh": "..." }], "feedback_zh": "..." }
      },
      "word_analysis": [
        {
          "word": "environment",
          "start_ms": 1240,
          "end_ms": 1890,
          "status": "warning",
          "ipa_target": "/ɪnˈvaɪrənmənt/",
          "issue_zh": "重音误放在第一音节，且尾音 /t/ 吞音过重"
        }
      ],
      "band_8_sample_answer": "..."
    }
    """

    /// 2. Part 2 智能串题与逐句 Diff System Prompt
    static let part2ClusteringSystemPrompt = """
    你是一位顶尖雅思口语教研专家，擅长“一材多用（Part 2 串题）”教学法。
    你将收到：
    1. 用户的个人真实中文经历背景；
    2. 目标分数（如 7.0）；
    3. 一组主题相关联的雅思 Part 2 话题卡列表（含各自 Cue Card 提示点）。

    【任务要求】
    1. 基于用户的真实经历，先提炼出一篇自然地道、细节饱满、符合目标分数的英文「核心万能素材（master_story）」。
    2. 将该万能素材分别适配改写到列表中的每一道 Part 2 题目中，确保 100% 紧扣每道题的 Cue Card 提问要求。
    3. 改写时最大化保留万能素材的通用主体段落，仅调整开头破题句、局部过渡句和结尾点题句。
    4. 将每道题的最终英文回答拆分为句子数组，明确标记哪些句子是直接复用的（"is_adapted": false），哪些是为了适配当前题目而修改的（"is_adapted": true），以便前端高亮展示差异。
    5. 严格输出纯 JSON 格式：

    {
      "master_story": {
        "en": "...",
        "zh": "...",
        "key_vocabulary": [{ "phrase": "...", "meaning_zh": "..." }]
      },
      "adapted_topics": [
        {
          "topic_id": "p2_01",
          "topic_title": "Describe a person who inspired you",
          "sentences": [
            { "en": "...", "zh": "...", "is_adapted": true },
            { "en": "...", "zh": "...", "is_adapted": false }
          ]
        }
      ]
    }
    """

    /// 3. 个性化答案定制 System Prompt
    static let customAnswerSystemPrompt = """
    你是一位资深雅思口语定制导师，擅长帮助中国考生“说你自己的故事”，生成去模板化、地道自然的专属雅思口语答案。
    请严格返回纯 JSON，不要包含 Markdown 代码块：
    {
      "answer_en": "...",
      "answer_zh": "...",
      "highlights": [
        { "phrase": "...", "explanation_zh": "..." }
      ],
      "coach_note_zh": "..."
    }
    """

    /// 4. 全真模考 Part 3 动态追问 System Prompt
    static let part3FollowUpSystemPrompt = """
    你是雅思口语考官。请先听取考生在 Part 2 中的音频陈述，提炼其核心内容，然后结合其回答细节生成 4 到 5 个层层递进、抽象度逐步提升的 Part 3 深度追问（英文）。
    严格输出纯 JSON：
    {
      "summary_of_part2": "...",
      "questions": ["...", "...", "...", "..."]
    }
    """

    // MARK: - 业务方法 1：单题音频四维评分 + 逐词纠音

    func evaluateAudioAnswer(
        audioURL: URL,
        part: IELTSPart,
        topicTitle: String,
        promptText: String,
        cueCardBullets: [String] = []
    ) async throws -> IELTSScoringResponseDTO {
        let apiKey = try requireAPIKey()
        let audioPart = try await buildAudioPart(from: audioURL, apiKey: apiKey)

        var userText = """
        【考试部分】\(part.title)
        【话题标题】\(topicTitle)
        【题目内容】\(promptText)
        """
        if !cueCardBullets.isEmpty {
            userText += "\n【Cue Card 提示点】\n" + cueCardBullets.map { "- \($0)" }.joined(separator: "\n")
        }
        userText += "\n请严格按照系统指令直接分析所附音频并返回纯 JSON。"

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.ieltsScoringSystemPrompt,
            parts: [
                .text(userText),
                audioPart
            ],
            temperature: 0.2
        )
        return try decodeStrictJSON(IELTSScoringResponseDTO.self, from: rawJSON)
    }

    // MARK: - 业务方法 2：全真模考三阶段汇总评估

    func evaluateFullMockExam(
        audioURLs: [URL],
        part1Summary: String,
        part2Topic: String,
        part3Questions: [String]
    ) async throws -> IELTSScoringResponseDTO {
        let apiKey = try requireAPIKey()
        var parts: [RequestPart] = []

        let contextText = """
        这是一场完整的 1:1 雅思口语全真模拟考试（含 Part 1、Part 2、Part 3 连续录音）。
        - Stage 1 (Part 1 题目): \(part1Summary)
        - Stage 2 (Part 2 话题卡): \(part2Topic)
        - Stage 3 (Part 3 追问): \(part3Questions.joined(separator: " | "))
        请综合全部录音片段的表现，严格按照雅思官方四维标准给出整场模考的最终总分、四项细分得分、核心逐词发音诊断（优先覆盖 Part 2/3 代表性失误词与关键句时间戳）及 8 分示范升级思路。严格返回纯 JSON。
        """
        parts.append(.text(contextText))

        for url in audioURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                let audioPart = try await buildAudioPart(from: url, apiKey: apiKey)
                parts.append(audioPart)
            }
        }

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.ieltsScoringSystemPrompt,
            parts: parts,
            temperature: 0.2
        )
        return try decodeStrictJSON(IELTSScoringResponseDTO.self, from: rawJSON)
    }

    // MARK: - 业务方法 3：Part 2 智能串题 + 逐句 Diff

    func generatePart2ClusterAdaptation(
        userStoryZh: String,
        targetBand: Double,
        topics: [(id: String, title: String, bullets: [String])]
    ) async throws -> Part2ClusteringResponseDTO {
        let apiKey = try requireAPIKey()

        let topicLines = topics.map { topic in
            let bulletText = topic.bullets.map { "  * \($0)" }.joined(separator: "\n")
            return "- topic_id: \(topic.id)\n  topic_title: \(topic.title)\n  cue_card_bullets:\n\(bulletText)"
        }.joined(separator: "\n\n")

        let userPrompt = """
        【用户真实中文经历】
        \(userStoryZh)

        【目标分数】
        Band \(String(format: "%.1f", targetBand))

        【待串联的 Part 2 话题卡列表】
        \(topicLines)

        请生成核心万能素材（master_story）并为每道题完成逐句适配与 is_adapted 标记，严格输出纯 JSON。
        """

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.part2ClusteringSystemPrompt,
            parts: [.text(userPrompt)],
            temperature: 0.4
        )
        return try decodeStrictJSON(Part2ClusteringResponseDTO.self, from: rawJSON)
    }

    // MARK: - 业务方法 4：个性化答案定制 & 多轮微调

    func generateCustomAnswer(
        part: IELTSPart,
        topicTitle: String,
        promptText: String,
        userStoryZh: String,
        targetBand: Double,
        styleMode: String
    ) async throws -> CustomAnswerResponseDTO {
        let apiKey = try requireAPIKey()

        let userPrompt = """
        【题目部分】\(part.title)
        【话题标题】\(topicTitle)
        【原题描述】\(promptText)
        【用户中文碎片想法/个人真实经历】\(userStoryZh)
        【目标分数】Band \(String(format: "%.1f", targetBand))
        【表达风格】\(styleMode)

        请结合用户真实经历生成地道、去模板化的英文回答 + 中文对照 + 核心亮点词句解析（至少 4 个亮点）+ 考官教练提分提示。
        """

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.customAnswerSystemPrompt,
            parts: [.text(userPrompt)],
            temperature: 0.55
        )
        return try decodeStrictJSON(CustomAnswerResponseDTO.self, from: rawJSON)
    }

    func refineCustomAnswer(
        topicTitle: String,
        currentAnswerEn: String,
        targetBand: Double,
        styleMode: String,
        refinementInstruction: String
    ) async throws -> CustomAnswerResponseDTO {
        let apiKey = try requireAPIKey()

        let userPrompt = """
        【当前题目】\(topicTitle)
        【目标分数】Band \(String(format: "%.1f", targetBand))（风格：\(styleMode)）
        【当前版本英文答案】
        \(currentAnswerEn)

        【用户本轮微调指令】
        \(refinementInstruction)

        请严格按照用户的微调指令修改上述答案，保留用户真实经历内核，并输出更新后的完整 JSON（包含 answer_en, answer_zh, highlights, coach_note_zh）。
        """

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.customAnswerSystemPrompt,
            parts: [.text(userPrompt)],
            temperature: 0.45
        )
        return try decodeStrictJSON(CustomAnswerResponseDTO.self, from: rawJSON)
    }

    // MARK: - 业务方法 5：根据 Part 2 音频动态生成 Part 3 追问

    func generatePart3FollowUpQuestions(
        part2AudioURL: URL,
        part2TopicTitle: String
    ) async throws -> Part3FollowUpResponseDTO {
        let apiKey = try requireAPIKey()
        let audioPart = try await buildAudioPart(from: part2AudioURL, apiKey: apiKey)

        let prompt = """
        考生刚刚完成了 Part 2 话题「\(part2TopicTitle)」的 2 分钟陈述（见音频）。
        请结合音频中的具体观点与细节，提出 4 到 5 个高质量的雅思 Part 3 深度抽象追问。
        """

        let rawJSON = try await generateStructuredJSON(
            apiKey: apiKey,
            systemPrompt: Self.part3FollowUpSystemPrompt,
            parts: [.text(prompt), audioPart],
            temperature: 0.4
        )
        return try decodeStrictJSON(Part3FollowUpResponseDTO.self, from: rawJSON)
    }

    // MARK: - 音频封装：自动选择 Inline Base64 或 Gemini File API

    private func buildAudioPart(from fileURL: URL, apiKey: String) async throws -> RequestPart {
        guard let audioData = try? Data(contentsOf: fileURL), !audioData.isEmpty else {
            throw GeminiServiceError.audioFileReadFailed
        }

        if audioData.count <= inlineDataThresholdBytes {
            return .inlineData(mimeType: "audio/mp4", base64: audioData.base64EncodedString())
        } else {
            let fileURI = try await uploadAudioViaFileAPI(
                data: audioData,
                displayName: fileURL.lastPathComponent,
                mimeType: "audio/mp4",
                apiKey: apiKey
            )
            return .fileData(mimeType: "audio/mp4", fileURI: fileURI)
        }
    }

    /// Gemini File API Resumable Upload（适用于长时全真模考大音频）
    private func uploadAudioViaFileAPI(
        data: Data,
        displayName: String,
        mimeType: String,
        apiKey: String
    ) async throws -> String {
        guard let startURL = URL(string: "\(baseURL)/upload/v1beta/files?key=\(apiKey)") else {
            throw GeminiServiceError.invalidURL
        }

        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startReq.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startReq.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startReq.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = ["file": ["display_name": displayName]]
        startReq.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, startResp) = try await session.data(for: startReq)
        guard let httpStart = startResp as? HTTPURLResponse,
              (200...299).contains(httpStart.statusCode),
              let uploadURLString = httpStart.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiServiceError.fileUploadFailed("初始化 Resumable Upload 失败")
        }

        var uploadReq = URLRequest(url: uploadURL)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        uploadReq.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadReq.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadReq.httpBody = data

        let (uploadData, uploadResp) = try await session.data(for: uploadReq)
        guard let httpUpload = uploadResp as? HTTPURLResponse,
              (200...299).contains(httpUpload.statusCode) else {
            let msg = String(data: uploadData, encoding: .utf8) ?? "未知错误"
            throw GeminiServiceError.fileUploadFailed(msg)
        }

        struct FileUploadEnvelope: Decodable {
            struct FileObj: Decodable { let uri: String }
            let file: FileObj
        }
        let parsed = try JSONDecoder().decode(FileUploadEnvelope.self, from: uploadData)
        return parsed.file.uri
    }

    // MARK: - 底层 REST 请求与 JSON 解析

    private enum RequestPart {
        case text(String)
        case inlineData(mimeType: String, base64: String)
        case fileData(mimeType: String, fileURI: String)

        var jsonObject: [String: Any] {
            switch self {
            case .text(let value):
                return ["text": value]
            case .inlineData(let mime, let base64):
                return ["inline_data": ["mime_type": mime, "data": base64]]
            case .fileData(let mime, let uri):
                return ["file_data": ["mime_type": mime, "file_uri": uri]]
            }
        }
    }

    private func generateStructuredJSON(
        apiKey: String,
        systemPrompt: String,
        parts: [RequestPart],
        temperature: Double
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1beta/models/\(modelName):generateContent?key=\(apiKey)") else {
            throw GeminiServiceError.invalidURL
        }

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": parts.map { $0.jsonObject }
                ]
            ],
            "generationConfig": [
                "temperature": temperature,
                "responseMimeType": "application/json"
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.emptyResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errText = String(data: data, encoding: .utf8) ?? "无详细错误信息"
            throw GeminiServiceError.httpError(statusCode: httpResponse.statusCode, message: errText)
        }

        struct GenerateResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }

        let envelope = try JSONDecoder().decode(GenerateResponse.self, from: data)
        guard let text = envelope.candidates?.first?.content.parts.compactMap(\.text).joined(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiServiceError.emptyResponse
        }
        return sanitizeJSON(text)
    }

    private func sanitizeJSON(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeStrictJSON<T: Decodable>(_ type: T.Type, from rawJSON: String) throws -> T {
        guard let data = rawJSON.data(using: .utf8) else {
            throw GeminiServiceError.emptyResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GeminiServiceError.decodingFailed(rawText: rawJSON, underlying: error)
        }
    }

    private func requireAPIKey() throws -> String {
        guard let key = KeychainManager.shared.loadAPIKey(), !key.isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }
        return key
    }
}
