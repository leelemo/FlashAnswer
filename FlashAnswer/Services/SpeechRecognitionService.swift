import Speech
import AVFoundation

protocol SpeechRecognitionDelegate: AnyObject {
    func didRecognize(text: String)
    func didFail(error: Error)
}

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

    /// 最长监听时间（秒），兜底防止无限监听
    private let maxListenDuration: TimeInterval = 30
    /// 静默时间（秒），停顿超过此时长立即触发匹配
    private let silenceDuration: TimeInterval = 1.5
    /// 停止词，识别到后立即触发匹配
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

                    // 检查停止词
                    if text.lowercased().contains(self.stopWord) {
                        let cleaned = text.replacingOccurrences(of: self.stopWord, with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
                        self.fireFinal(text: cleaned.isEmpty ? text : cleaned)
                        return
                    }

                    // 有有效文字变化就重置静默定时器
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

    // MARK: - Silence detection (1.5s 静默触发)

    private func resetSilenceTimer(text: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
            self?.fireFinal(text: text)
        }
    }

    // MARK: - Max listen timeout (兜底)

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
            // 空文字不触发匹配，但也要停止当前轮让 ViewModel 重启
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
