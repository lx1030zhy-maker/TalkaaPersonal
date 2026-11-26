# Talkaa 个人版（iPhone 17 · Swift 6 + Gemini 4 Neon）

纯端侧无服务器架构的个人专属雅思口语 AI 陪练 iOS 应用，完整复刻 Talkaa 七大核心模块，直连 Google `gemini-4-neon` 多模态音频理解与结构化 JSON 输出能力。

## 核心技术栈
- **语言与架构**：Swift 6 (`STRICT_CONCURRENCY = complete`) + SwiftUI + SwiftData + Swift Charts
- **音频引擎**：`AVAudioRecorder`（24kHz 单声道 `.m4a` AAC + 实时分贝波形）+ `AVAudioPlayer`（毫秒级 `start_ms`/`end_ms` 点词切片回放）+ `AVSpeechSynthesizer`（英/美/澳考官读题与跟读对照）+ `SFSpeechRecognizer`（中文语音转文字）
- **安全与无后端**：API Key 加密存储于 iOS `Keychain`；本地 `SwiftData` 持久化全部真题、评分记录、定制答案、串题分组与素材库
- **iPhone 17 体验**：ProMotion 120Hz 丝滑脉冲波形 + `ActivityKit` 灵动岛实时显示 Part 2 1 分钟准备 / 2 分钟陈述倒计时

## 快速构建与真机运行（Xcode）

### 方式一：使用 XcodeGen 一键生成 `.xcodeproj`（推荐）
```bash
brew install xcodegen
cd TalkaaPersonal
xcodegen generate
open TalkaaPersonal.xcodeproj
```

### 方式二：在 Xcode 中手动新建项目导入源码
1. 打开 Xcode，新建 **iOS App**（Interface: SwiftUI，Language: Swift，Storage: SwiftData），命名为 `TalkaaPersonal`。
2. 将本压缩包中的 `TalkaaPersonal/` 源码目录拖入主 App Target；如需灵动岛功能，添加 **Widget Extension（勾选 Include Live Activity）** Target 并替换为 `TalkaaLiveActivityWidget/` 中的文件，同时确保 `TalkaaLiveActivityAttributes.swift` 勾选加入两个 Target 的 Target Membership。
3. 在主 Target 的 `Signing & Capabilities` 中选择你的个人 Apple ID Team（Personal Team 即可免费真机安装至 iPhone 17）。
4. 连接 iPhone 17，点击 Run (`⌘R`)。

## 首次使用配置
1. 打开 App 后，点击右上角齿轮图标进入 **「设置」**。
2. 粘贴你的 Google AI Studio API Key 并点击 **「安全保存到 Keychain」**。
3. 默认模型标识为 `gemini-4-neon`（若需临时切换其他多模态模型，可在设置页直接修改）。
4. 可在题库页或设置页导入 `TalkaaPersonal/Resources/sample_question_bank.json` 测试当季外部 JSON 题库一键更新。
