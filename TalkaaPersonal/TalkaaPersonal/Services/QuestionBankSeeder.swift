import Foundation
import SwiftData

@MainActor
enum QuestionBankSeeder {

    static func seedIfNeeded(modelContext: ModelContext) {
        let existingQuestions = (try? modelContext.fetchCount(FetchDescriptor<IELTSQuestion>())) ?? 0
        if existingQuestions == 0 {
            for q in initialQuestions() {
                modelContext.insert(q)
            }
        }

        let existingClusters = (try? modelContext.fetchCount(FetchDescriptor<TopicClusterGroup>())) ?? 0
        if existingClusters == 0 {
            for c in initialClusterGroups() {
                modelContext.insert(c)
            }
        }

        let existingVault = (try? modelContext.fetchCount(FetchDescriptor<StudyVaultItem>())) ?? 0
        if existingVault == 0 {
            for v in initialStudyVaultItems() {
                modelContext.insert(v)
            }
        }

        try? modelContext.save()
    }

    /// 一键导入外部 JSON 当季题库包
    static func importExternalJSON(from url: URL, modelContext: ModelContext) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ExternalQuestionBankFileDTO.self, from: data)

        let existing = (try? modelContext.fetch(FetchDescriptor<IELTSQuestion>())) ?? []
        let existingCodes = Set(existing.map(\.questionCode))

        var insertedCount = 0
        for item in decoded.questions {
            guard !existingCodes.contains(item.id) else { continue }
            let part = IELTSPart(rawValue: item.part) ?? .part1
            let question = IELTSQuestion(
                questionCode: item.id,
                part: part,
                category: item.category,
                topicTitle: item.topicTitle,
                promptText: item.promptText,
                cueCardBullets: item.cueCardBullets ?? [],
                subQuestions: item.subQuestions ?? [],
                isHighFrequency: item.isHighFrequency ?? false,
                targetBandTag: item.targetBandTag ?? 7.0,
                isPracticed: false,
                clusterGroupName: item.clusterGroupName ?? "",
                seasonTag: decoded.season
            )
            modelContext.insert(question)
            insertedCount += 1
        }
        try modelContext.save()
        return insertedCount
    }

    // MARK: - 内置初始真题（Part 1 / 2 / 3 各至少 5 组完整题组）

    private static func initialQuestions() -> [IELTSQuestion] {
        [
            // ===== PART 1 (5 组完整题组) =====
            IELTSQuestion(
                questionCode: "p1_01",
                part: .part1,
                category: "工作与学习",
                topicTitle: "Work or Studies",
                promptText: "Do you work or are you a student? What do you like most about your job or major?",
                subQuestions: [
                    "Do you work or are you a student?",
                    "Why did you choose your current job or major?",
                    "What is the most challenging part of your daily routine?",
                    "Do you plan to change your field in the next few years?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0
            ),
            IELTSQuestion(
                questionCode: "p1_02",
                part: .part1,
                category: "居住与城市",
                topicTitle: "Hometown & Living Space",
                promptText: "Where is your hometown? Has it changed much since you were a child?",
                subQuestions: [
                    "Can you describe the area where you currently live?",
                    "What do you like most about your hometown?",
                    "Has your hometown changed much in recent years?",
                    "Would you say it is a good place for young people to live?"
                ],
                isHighFrequency: true,
                targetBandTag: 6.5
            ),
            IELTSQuestion(
                questionCode: "p1_03",
                part: .part1,
                category: "科技与日常",
                topicTitle: "Apps & Smartphones",
                promptText: "What mobile apps do you use most frequently in your daily life?",
                subQuestions: [
                    "Which app do you spend the most time on every day?",
                    "Do you prefer learning through apps or traditional books?",
                    "Have you ever paid for a subscription app?",
                    "Do you think people rely too heavily on smartphones nowadays?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0
            ),
            IELTSQuestion(
                questionCode: "p1_04",
                part: .part1,
                category: "休闲与兴趣",
                topicTitle: "Coffee, Tea & Cafes",
                promptText: "Do you prefer drinking coffee or tea? How often do you visit cafes?",
                subQuestions: [
                    "Do people in your country prefer coffee or tea?",
                    "When was the last time you went to a coffee shop?",
                    "Do you like studying or working in a cafe?",
                    "What kind of atmosphere do you look for in a cafe?"
                ],
                isHighFrequency: false,
                targetBandTag: 6.5
            ),
            IELTSQuestion(
                questionCode: "p1_05",
                part: .part1,
                category: "生活习惯",
                topicTitle: "Morning Routine & Sleep",
                promptText: "Are you a morning person or a night owl? What is the first thing you do after waking up?",
                subQuestions: [
                    "What time do you usually get up on weekdays?",
                    "Do you think having a fixed morning routine is important?",
                    "How do you usually feel if you don't get enough sleep?",
                    "Has your sleep schedule changed compared to a few years ago?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5
            ),

            // ===== PART 2 (6 组完整 Cue Card，覆盖三大核心串题分组) =====
            IELTSQuestion(
                questionCode: "p2_01",
                part: .part2,
                category: "人物类",
                topicTitle: "Describe a person who inspired you to do something interesting",
                promptText: "Describe a person who inspired you to try something new or interesting.",
                cueCardBullets: [
                    "Who this person is",
                    "How you know this person",
                    "What interesting thing they inspired you to do",
                    "And explain how you felt about it"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0,
                clusterGroupName: "一个难忘的人"
            ),
            IELTSQuestion(
                questionCode: "p2_02",
                part: .part2,
                category: "人物类",
                topicTitle: "Describe an intelligent person you know",
                promptText: "Describe a person you know who is very smart or knowledgeable.",
                cueCardBullets: [
                    "Who this person is",
                    "How you met them",
                    "What makes you think they are intelligent",
                    "And explain what you have learned from them"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5,
                clusterGroupName: "一个难忘的人"
            ),
            IELTSQuestion(
                questionCode: "p2_03",
                part: .part2,
                category: "地点与旅行",
                topicTitle: "Describe an unforgettable trip you took with friends or family",
                promptText: "Describe a memorable journey you went on that you would like to take again.",
                cueCardBullets: [
                    "Where you went",
                    "Who you went with",
                    "What you did during the trip",
                    "And explain why it was so unforgettable"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0,
                clusterGroupName: "一次旅行经历"
            ),
            IELTSQuestion(
                questionCode: "p2_04",
                part: .part2,
                category: "地点与旅行",
                topicTitle: "Describe a noisy or crowded place you have visited",
                promptText: "Describe a lively or crowded place you visited recently.",
                cueCardBullets: [
                    "Where this place is",
                    "When you went there",
                    "What people were doing there",
                    "And explain how you felt about being in this place"
                ],
                isHighFrequency: false,
                targetBandTag: 6.5,
                clusterGroupName: "一次旅行经历"
            ),
            IELTSQuestion(
                questionCode: "p2_05",
                part: .part2,
                category: "物品类",
                topicTitle: "Describe an important piece of technology you find difficult to live without",
                promptText: "Describe a gadget or piece of technology that plays a vital role in your daily life.",
                cueCardBullets: [
                    "What the item is",
                    "When you first got it",
                    "How often you use it and what for",
                    "And explain why it is so meaningful or essential to you"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0,
                clusterGroupName: "一件有意义的物品"
            ),
            IELTSQuestion(
                questionCode: "p2_06",
                part: .part2,
                category: "物品类",
                topicTitle: "Describe a special gift you received that you still treasure",
                promptText: "Describe a meaningful gift someone gave you that you have kept for a long time.",
                cueCardBullets: [
                    "What the gift was",
                    "Who gave it to you and on what occasion",
                    "How you use or keep it",
                    "And explain why you treasure it so much"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5,
                clusterGroupName: "一件有意义的物品"
            ),

            // ===== PART 3 (5 组深度抽象讨论题组) =====
            IELTSQuestion(
                questionCode: "p3_01",
                part: .part3,
                category: "教育与榜样",
                topicTitle: "Role Models & Mentorship in Modern Society",
                promptText: "How do role models influence young people's career and life choices differently today compared to the past?",
                subQuestions: [
                    "What qualities make someone a truly inspiring role model?",
                    "Do you think social media influencers have too much impact on teenagers?",
                    "Should schools invite more professionals from outside to mentor students?",
                    "Is intrinsic motivation more reliable than external inspiration?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5
            ),
            IELTSQuestion(
                questionCode: "p3_02",
                part: .part3,
                category: "旅游与文化",
                topicTitle: "Tourism Impact & Cultural Preservation",
                promptText: "Does mass tourism do more harm than good to historical cities and local communities?",
                subQuestions: [
                    "Why do people today travel more frequently than previous generations?",
                    "How can governments balance economic benefits of tourism with environmental protection?",
                    "Do you think virtual reality travel will ever replace physical journeys?",
                    "What can tourists do to respect local traditions?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.0
            ),
            IELTSQuestion(
                questionCode: "p3_03",
                part: .part3,
                category: "科技与人工智能",
                topicTitle: "AI, Automation & Human Creativity",
                promptText: "To what extent will artificial intelligence change the skills people need in the workplace over the next decade?",
                subQuestions: [
                    "Which jobs are least likely to be replaced by AI?",
                    "Should governments regulate the pace of AI adoption?",
                    "Does technology make people more isolated or more connected?",
                    "How can older generations be helped to adapt to rapid digital transformation?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5
            ),
            IELTSQuestion(
                questionCode: "p3_04",
                part: .part3,
                category: "消费与价值观",
                topicTitle: "Materialism & Meaningful Possessions",
                promptText: "Why do some people attach strong emotional value to everyday objects while others prefer minimalism?",
                subQuestions: [
                    "Do advertisements encourage people to buy things they don't actually need?",
                    "Are handmade gifts more appreciated than expensive store-bought items?",
                    "How has online shopping transformed consumer habits?",
                    "Do you think younger generations are becoming more environmentally conscious consumers?"
                ],
                isHighFrequency: false,
                targetBandTag: 7.0
            ),
            IELTSQuestion(
                questionCode: "p3_05",
                part: .part3,
                category: "城市与生活节奏",
                topicTitle: "Urbanization & Work-Life Balance",
                promptText: "Why do many young professionals still choose to live in fast-paced megacities despite high living costs?",
                subQuestions: [
                    "What are the biggest challenges cities face as populations grow?",
                    "How does remote work affect urban housing and commuting?",
                    "Should companies be legally required to restrict after-hours work messages?",
                    "What makes a city truly livable in the long term?"
                ],
                isHighFrequency: true,
                targetBandTag: 7.5
            )
        ]
    }

    private static func initialClusterGroups() -> [TopicClusterGroup] {
        [
            TopicClusterGroup(
                groupName: "一个难忘的人",
                groupDescription: "用同一位导师/朋友/家人的真实人物故事，一键串联「启发你的人」「聪明的人」「敬佩的职场人」等多道人物卡。",
                iconName: "person.2.fill",
                userStoryZh: "",
                targetBand: 7.0
            ),
            TopicClusterGroup(
                groupName: "一次旅行经历",
                groupDescription: "用同一次印象深刻的深度自由行，串联「难忘的旅行」「热闹的地点」「想再去一次的地方」等地点卡。",
                iconName: "airplane.departure",
                userStoryZh: "",
                targetBand: 7.0
            ),
            TopicClusterGroup(
                groupName: "一件有意义的物品",
                groupDescription: "用同一件陪伴成长的随身科技好物或礼物，串联「离不开的科技产品」「珍藏的礼物」「存钱买的东西」等物品卡。",
                iconName: "gift.fill",
                userStoryZh: "",
                targetBand: 7.0
            )
        ]
    }

    private static func initialStudyVaultItems() -> [StudyVaultItem] {
        [
            // 高频连接词
            StudyVaultItem(
                category: "高频连接词",
                partScope: "Part 1",
                titleEn: "To be completely honest / Come to think of it",
                meaningZh: "说实话 / 仔细一想（自然争取思考时间，替代干硬的 um/uh）",
                exampleEn: "Come to think of it, I probably spend far too much time scrolling through news apps before breakfast."
            ),
            StudyVaultItem(
                category: "高频连接词",
                partScope: "Part 2",
                titleEn: "What really stood out to me was...",
                meaningZh: "真正令我印象深刻的是……（Part 2 高分细节切入句）",
                exampleEn: "What really stood out to me was how effortlessly she turned a stressful crisis into a learning opportunity."
            ),
            StudyVaultItem(
                category: "高频连接词",
                partScope: "Part 3",
                titleEn: "That's a nuanced issue; on the one hand..., yet on the other...",
                meaningZh: "这是一个需要辩证看待的问题；一方面……另一方面……（Part 3 双边论证）",
                exampleEn: "That's a nuanced issue; on the one hand, mass tourism boosts local revenue, yet on the other, it strains public infrastructure."
            ),
            // 地道习语
            StudyVaultItem(
                category: "地道习语",
                partScope: "通用",
                titleEn: "hit the ground running",
                meaningZh: "迅速进入状态、旗开得胜",
                exampleEn: "Thanks to her guidance, I was able to hit the ground running during my first week at the new company."
            ),
            StudyVaultItem(
                category: "地道习语",
                partScope: "Part 2",
                titleEn: "a breath of fresh air",
                meaningZh: "令人耳目一新的人或事物",
                exampleEn: "Escaping the concrete jungle for that quiet coastal town felt like a breath of fresh air."
            ),
            StudyVaultItem(
                category: "地道习语",
                partScope: "Part 3",
                titleEn: "a double-edged sword",
                meaningZh: "一把双刃剑（讨论科技/社媒/AI 必备）",
                exampleEn: "Generative AI is undeniably a double-edged sword when it comes to entry-level creative jobs."
            ),
            // 万金油答题框架
            StudyVaultItem(
                category: "万金油框架",
                partScope: "Part 1",
                titleEn: "A-R-E 三步法 (Answer → Reason → Example)",
                meaningZh: "直接回答 + 核心原因 + 1句个人微场景，确保 20–30 秒自然饱满不啰嗦。",
                exampleEn: "Yes, I'm definitely a coffee person. It gives me a gentle mental boost in the morning—just yesterday I brewed a pour-over before my 9 a.m. meeting."
            ),
            StudyVaultItem(
                category: "万金油框架",
                partScope: "Part 2",
                titleEn: "时间轴 + 情绪转折结构 (Hook → Background → Turning Point → Reflection)",
                meaningZh: "10秒破题 + 30秒背景铺垫 + 50秒核心高潮细节 + 30秒收获感悟，稳撑 2 分钟不卡壳。",
                exampleEn: "Hook: I'd love to tell you about... -> Turning Point: At first I hesitated, but then... -> Reflection: Looking back, that moment shaped how I..."
            ),
            StudyVaultItem(
                category: "万金油框架",
                partScope: "Part 3",
                titleEn: "P-E-C-C 深度论证 (Point → Explain → Contrast → Consequence)",
                meaningZh: "亮明立场 + 逻辑展开 + 过去/现在或群体对比 + 长期社会影响。",
                exampleEn: "Point: Urban living still attracts youth -> Contrast: Unlike two decades ago when job security came first, young graduates now value networking opportunities..."
            )
        ]
    }
}
