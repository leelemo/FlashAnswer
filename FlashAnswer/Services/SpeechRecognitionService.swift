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

    /// 最长监听时间（秒），超时后自动重置
    private let maxListenDuration: TimeInterval = 20
    /// 部分结果最短有效长度，短于此长度的变化不重置静默定时器（噪音过滤）
    private let minMeaningfulLength = 2

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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true  // 纯设备端，后台可用
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
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.lastTranscription {
                    self.lastTranscription = text
                    // 噪音过滤：只有有意义的变化才重置静默定时器
                    if self.isMeaningfulText(text) {
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

    // MARK: - Silence detection

    private func resetSilenceTimer(text: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.fireFinal(text: text)
        }
    }

    // MARK: - Max listen timeout

    private func startMaxListenTimer() {
        maxListenTimer?.invalidate()
        maxListenTimer = Timer.scheduledTimer(withTimeInterval: maxListenDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 超时后，如果有有意义的识别文字就用它匹配，否则直接重置
            let text = self.lastTranscription
            if self.isMeaningfulText(text) {
                self.fireFinal(text: text)
            } else {
                // 没有有意义的内容，通知 delegate 失败让其重启
                self.stopListening()
                self.delegate?.didFail(error: NSError(domain: "FlashAnswer", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "监听超时，未识别到内容"]))
            }
        }
    }

    // MARK: - Noise filtering

    /// 判断部分结果是否足够有意义以重置静默定时器
    private func isMeaningfulText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 太短的变化（如单字、标点）视为噪音，不重置定时器
        guard trimmed.count >= minMeaningfulLength else { return false }
        // 纯标点/符号不算
        let hasContent = trimmed.unicodeScalars.contains { !$0.properties.isWhitespace && !CharacterSet.punctuationCharacters.contains($0) }
        return hasContent
    }

    private func fireFinal(text: String) {
        guard !text.isEmpty else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        delegate?.didRecognize(text: text)
        // Stop so ViewModel can restart for next round
        stopListening()
    }
}
