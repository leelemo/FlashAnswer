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
    private var lastTranscription = ""

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

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.lastTranscription {
                    self.lastTranscription = text
                    self.resetSilenceTimer(text: text)
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

    private func fireFinal(text: String) {
        guard !text.isEmpty else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        delegate?.didRecognize(text: text)
        // Stop so ViewModel can restart for next round
        stopListening()
    }
}
