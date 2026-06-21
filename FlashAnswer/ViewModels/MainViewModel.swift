import Foundation
import Combine

enum AppState {
    case idle
    case listening
    case matched(results: [QuestionBank.MatchResult])
    case noMatch(text: String)
    case error(String)
}

class MainViewModel: NSObject, ObservableObject, SpeechRecognitionDelegate {
    @Published var state: AppState = .idle
    @Published var isListening = false
    @Published var statusText = "就绪"
    @Published var permissionsGranted = false

    let bank = QuestionBank()
    private let speech = SpeechRecognitionService()
    private let audio = AudioSessionService()
    private var restartTimer: Timer?

    override init() {
        super.init()
        speech.delegate = self
    }

    // MARK: - Permissions

    func requestPermissions() {
        speech.requestPermission { [weak self] speechOK in
            NotificationService.shared.requestPermission { notifOK in
                self?.permissionsGranted = speechOK && notifOK
                if !(speechOK && notifOK) {
                    self?.state = .error("请在设置中开启麦克风和通知权限")
                }
            }
        }
    }

    // MARK: - Import Excel

    func importExcel(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let questions = try ExcelParserService.parse(url: url)
            bank.importQuestions(questions)
            statusText = "已导入 \(bank.questions.count) 道题"
        } catch {
            state = .error("导入失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Clear bank

    func clearBank() {
        bank.clearAll()
        statusText = "题库已清空"
        state = .idle
    }

    // MARK: - Listening control

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !bank.questions.isEmpty else {
            state = .error("请先导入题库")
            return
        }
        audio.startBackgroundAudio()
        isListening = true
        statusText = "监听中..."
        state = .idle
        speech.startListening()
    }

    func stopListening() {
        isListening = false
        statusText = "已停止"
        speech.stopListening()
        audio.stop()
        restartTimer?.invalidate()
        restartTimer = nil
    }

    // MARK: - SpeechRecognitionDelegate

    func didRecognize(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let results = self.bank.match(recognizedText: text)
            if !results.isEmpty {
                self.state = .matched(results: results)
                NotificationService.shared.sendMatchedAnswers(results: results)
            } else {
                self.state = .noMatch(text: text)
                NotificationService.shared.sendNoMatch(recognizedText: text)
            }

            // 出答案后立即开始下一轮监听
            if self.isListening {
                self.scheduleAutoRestart()
            }
        }
    }

    func didFail(error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isListening {
                // 失败后短暂延迟再重启，避免频繁重试
                self.scheduleAutoRestart()
            }
        }
    }

    // MARK: - Auto restart (出答案后立即下一轮)

    private func scheduleAutoRestart() {
        restartTimer?.invalidate()
        // 延迟1秒让通知先发出去，然后立即开始下一轮
        restartTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self, self.isListening else { return }
            self.statusText = "监听中..."
            self.state = .idle
            self.speech.startListening()
        }
    }

    func restartNow() {
        restartTimer?.invalidate()
        guard isListening else { return }
        statusText = "监听中..."
        state = .idle
        speech.startListening()
    }
}
