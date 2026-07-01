import Foundation
import Combine

/// 识别模式
enum RecognitionMode: String, CaseIterable {
    case voice = "语音识别"
    case screen = "录屏识别"
}

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

    /// 当前识别模式
    @Published var mode: RecognitionMode = .voice {
        didSet {
            if isListening {
                stopListening()
            }
        }
    }

    /// 当前题型，默认单选题，跨监听轮次保持
    @Published var currentType = "单选题"

    let bank = QuestionBank()
    private let speech = SpeechRecognitionService()
    private let audio = AudioSessionService()
    private var restartTimer: Timer?

    /// 题型切换关键词
    static let typeKeywords: [(display: String, keywords: [String])] = [
        ("单选题", ["单选", "单选题"]),
        ("多选题", ["多选", "多选题"]),
        ("判断题", ["判断", "判断题"]),
    ]

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

    // MARK: - Listening control (语音模式)

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
        statusText = "监听中...（当前题型：\(currentType)）"
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

            // 匹配时按当前题型过滤
            let results = self.bank.match(recognizedText: text, typeFilter: self.currentType)
            if !results.isEmpty {
                self.state = .matched(results: results)
                NotificationService.shared.sendMatchedAnswers(results: results)
            } else {
                self.state = .noMatch(text: text)
                NotificationService.shared.sendNoMatch(recognizedText: text)
            }

            if self.isListening {
                self.scheduleAutoRestart()
            }
        }
    }

    /// 题型切换指令
    func didSwitchType(type: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentType = type
            self.statusText = "当前题型：\(type)"
            NotificationService.shared.sendTypeSwitched(type: type)

            // 切换后自动开始下一轮监听
            if self.isListening {
                self.scheduleAutoRestart()
            }
        }
    }

    func didFail(error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isListening {
                self.scheduleAutoRestart()
            }
        }
    }

    // MARK: - Auto restart

    private func scheduleAutoRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self, self.isListening else { return }
            self.statusText = "监听中...（当前题型：\(self.currentType)）"
            self.state = .idle
            self.speech.startListening()
        }
    }

    func restartNow() {
        restartTimer?.invalidate()
        guard isListening else { return }
        statusText = "监听中...（当前题型：\(currentType)）"
        state = .idle
        speech.startListening()
    }
}
