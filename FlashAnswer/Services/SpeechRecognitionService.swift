import Speech
import AVFoundation

protocol SpeechRecognitionDelegate: AnyObject {
    func didRecognize(text: String)
    func didSwitchType(type: String)
    func didFail(error: Error)
}

// 题型切换关键词
private let typeSwitchKeywords: [(type: String, keywords: [String])] = [
    ("单选题", ["单选", "单选题"]),
    ("多选题", ["多选", "多选题"]),
    ("判断题", ["判断", "判断题"]),
]

class SpeechRecognitionService: NSObject {
    weak var delegate: SpeechRecognitionDelegate?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: Timer?
    private var maxListenTimer: Timer?
    private var lastTranscription = ""
    private var hasFired = false

    private let maxListenDuration: TimeInterval = 30
    private let silenceDuration: TimeInterval = 1.5
    private let stopWord = "over"

    var isRunning: Bool { audioEngine.isRunning }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func startListening() {
        stopListening()
        hasFired = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        try? audioEngine.start()
        lastTranscription = ""
        startMaxListenTimer()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.hasFired else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.lastTranscription {
                    self.lastTranscription = text

                    // 检查停止词 "over"
                    if text.lowercased().contains(self.stopWord) {
                        let cleaned = text.replacingOccurrences(of: self.stopWord, with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)

                        // 先判断是否是题型切换指令（文字短 + 含题型关键词）
                        if let newType = self.detectTypeSwitch(text: cleaned) {
                            self.handleTypeSwitch(type: newType)
                            return
                        }

                        // 不是题型切换，正常触发匹配
                        self.fireFinal(text: cleaned.isEmpty ? text : cleaned)
                        return
                    }

                    // 没有"over"，重置静默定时器
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.resetSilenceTimer(text: text)
                    }
                }
                if result.isFinal {
                    self.fireFinal(text: text)
                }
            } else if let error {
                self.delegate?.didFail(error: error)
            }
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxListenTimer?.invalidate()
        maxListenTimer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }

    // MARK: - 题型切换检测

    /// 判断是否是题型切换指令：文字短 + 包含题型关键词
    private func detectTypeSwitch(text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 题型切换指令通常很短（≤8个字符）
        guard trimmed.count <= 8 else { return nil }

        for (type, keywords) in typeSwitchKeywords {
            for keyword in keywords {
                if trimmed.contains(keyword) {
                    return type
                }
            }
        }
        return nil
    }

    /// 处理题型切换：通知 delegate，不触发题目匹配
    private func handleTypeSwitch(type: String) {
        guard !hasFired else { return }
        hasFired = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxListenTimer?.invalidate()
        maxListenTimer = nil
        stopListening()
        delegate?.didSwitchType(type: type)
    }

    // MARK: - Silence detection

    private func resetSilenceTimer(text: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
            self?.fireFinal(text: text)
        }
    }

    // MARK: - Max listen timeout

    private func startMaxListenTimer() {
        maxListenTimer?.invalidate()
        maxListenTimer = Timer.scheduledTimer(withTimeInterval: maxListenDuration, repeats: false) { [weak self] _ in
            guard let self, !self.hasFired else { return }
            let text = self.lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                self.fireFinal(text: text)
            } else {
                self.stopListening()
                self.delegate?.didFail(error: NSError(domain: "FlashAnswer", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "监听超时，未识别到内容"]))
            }
        }
    }

    // MARK: - Fire final result

    private func fireFinal(text: String) {
        guard !hasFired else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hasFired = true
            silenceTimer?.invalidate()
            silenceTimer = nil
            maxListenTimer?.invalidate()
            maxListenTimer = nil
            stopListening()
            delegate?.didFail(error: NSError(domain: "FlashAnswer", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未识别到有效内容"]))
            return
        }
        hasFired = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxListenTimer?.invalidate()
        maxListenTimer = nil
        delegate?.didRecognize(text: text)
        stopListening()
    }
}
