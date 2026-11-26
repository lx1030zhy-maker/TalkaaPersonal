import Foundation
import AVFoundation
import Speech
import Observation

/// 负责 .m4a 音频录制、实时分贝波形、毫秒级切片播放、AI 考官 TTS 朗读及中文语音转文字
@MainActor
@Observable
final class AudioManager: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    // 录音状态
    var isRecording = false
    var currentAmplitude: Float = 0.0 // 0.0 ~ 1.0
    var waveformSamples: [Float] = Array(repeating: 0.08, count: 36)
    var recordingDuration: TimeInterval = 0
    var lastRecordedFileURL: URL?

    // 播放状态
    var isPlayingAudio = false
    var isPlayingSegment = false
    var isSpeakingTTS = false
    var playbackProgress: Double = 0

    // 语音转文字状态（用于“说你自己的故事”中文输入）
    var isDictating = false
    var dictatedText = ""

    var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()

    private var meteringTask: Task<Void, Never>?
    private var segmentStopTask: Task<Void, Never>?
    private var playbackProgressTask: Task<Void, Never>?
    private var ttsCompletion: (() -> Void)?

    // Speech-to-Text
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    // MARK: - 权限申请

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - 录制 24kHz 单声道 .m4a AAC 音频

    func startRecording(filePrefix: String = "practice") async -> URL? {
        stopAllPlayback()
        let granted = await requestMicrophonePermission()
        guard granted else {
            errorMessage = "请在系统设置中允许 Talkaa 个人版使用麦克风权限。"
            return nil
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let fileName = "\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).m4a"
            let fileURL = AudioStorageHelper.recordingsDirectory.appendingPathComponent(fileName)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 64_000
            ]

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()

            self.audioRecorder = recorder
            self.lastRecordedFileURL = fileURL
            self.isRecording = true
            self.recordingDuration = 0
            self.waveformSamples = Array(repeating: 0.08, count: 36)
            self.errorMessage = nil

            startMeteringLoop()
            return fileURL
        } catch {
            errorMessage = "启动录音失败：\(error.localizedDescription)"
            return nil
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        meteringTask?.cancel()
        meteringTask = nil

        guard let recorder = audioRecorder else { return nil }
        let finalDuration = max(recorder.currentTime, recordingDuration)
        let url = recorder.url
        recorder.stop()
        self.audioRecorder = nil
        self.isRecording = false
        self.currentAmplitude = 0
        self.lastRecordedFileURL = url

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        return (url, finalDuration)
    }

    func cancelRecording() {
        meteringTask?.cancel()
        meteringTask = nil
        if let recorder = audioRecorder {
            let url = recorder.url
            recorder.stop()
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        isRecording = false
        currentAmplitude = 0
        recordingDuration = 0
    }

    private func startMeteringLoop() {
        meteringTask?.cancel()
        meteringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { break }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0) // -160 dB ... 0 dB
                let normalized = Self.normalizeDecibels(power)
                self.currentAmplitude = normalized
                self.recordingDuration = recorder.currentTime
                var samples = self.waveformSamples
                samples.removeFirst()
                samples.append(max(0.08, normalized))
                self.waveformSamples = samples
                try? await Task.sleep(for: .milliseconds(33)) // ~30-60Hz 丝滑波形刷新
            }
        }
    }

    private static func normalizeDecibels(_ dB: Float) -> Float {
        let minDb: Float = -55.0
        if dB < minDb { return 0.05 }
        if dB >= 0 { return 1.0 }
        let linear = (dB - minDb) / abs(minDb)
        return pow(linear, 1.35)
    }

    // MARK: - 毫秒级时间戳精准切片回放（点词回放核心）

    func playSegment(url: URL, startMs: Int, endMs: Int) {
        stopAllPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()

            // 为防止切词过紧，前后保留 45ms 柔和余量并限制在音频合法区间内
            let safeStart = max(0, (Double(startMs) - 45.0) / 1000.0)
            let safeEnd = min(player.duration, (Double(endMs) + 60.0) / 1000.0)
            let clipDuration = max(0.22, safeEnd - safeStart)

            player.currentTime = safeStart
            player.play()

            self.audioPlayer = player
            self.isPlayingAudio = true
            self.isPlayingSegment = true

            segmentStopTask?.cancel()
            segmentStopTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(clipDuration * 1000)))
                guard !Task.isCancelled else { return }
                self?.stopAudioPlayer()
            }
        } catch {
            errorMessage = "切片音频播放失败：\(error.localizedDescription)"
        }
    }

    func playFullAudio(url: URL) {
        stopAllPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()

            self.audioPlayer = player
            self.isPlayingAudio = true
            self.isPlayingSegment = false
            self.playbackProgress = 0

            playbackProgressTask?.cancel()
            playbackProgressTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let p = self.audioPlayer, p.isPlaying else { break }
                    self.playbackProgress = p.duration > 0 ? (p.currentTime / p.duration) : 0
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            errorMessage = "原声播放失败：\(error.localizedDescription)"
        }
    }

    func stopAudioPlayer() {
        segmentStopTask?.cancel()
        playbackProgressTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        isPlayingSegment = false
        playbackProgress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingAudio = false
            self.isPlayingSegment = false
            self.playbackProgress = 0
        }
    }

    // MARK: - AI 考官与标准音 TTS 朗读

    func speakEnglish(_ text: String, rate: Float = 0.48, onFinished: (() -> Void)? = nil) {
        stopAllPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let accent = UserDefaults.standard.string(forKey: "examiner_accent") ?? "en-GB"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: accent) ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0

        self.ttsCompletion = onFinished
        self.isSpeakingTTS = true
        speechSynthesizer.speak(utterance)
    }

    func stopTTS() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeakingTTS = false
        ttsCompletion = nil
    }

    func stopAllPlayback() {
        stopAudioPlayer()
        stopTTS()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeakingTTS = false
            let callback = self.ttsCompletion
            self.ttsCompletion = nil
            callback?()
        }
    }

    // MARK: - 中文语音转文字（“说你自己的故事”语音输入）

    func startChineseDictation(onUpdate: @escaping @MainActor (String) -> Void) async {
        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micAuth = await requestMicrophonePermission()
        guard speechAuth && micAuth else {
            errorMessage = "需要麦克风与语音识别权限才能使用语音转文字。"
            return
        }

        stopChineseDictation()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isDictating = true
            dictatedText = ""

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.dictatedText = text
                        onUpdate(text)
                    }
                    if error != nil || (result?.isFinal == true) {
                        self.stopChineseDictation()
                    }
                }
            }
        } catch {
            errorMessage = "语音识别启动失败：\(error.localizedDescription)"
            stopChineseDictation()
        }
    }

    func stopChineseDictation() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isDictating = false
    }
}
