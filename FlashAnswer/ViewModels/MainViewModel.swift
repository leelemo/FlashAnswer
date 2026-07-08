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

    /// 录屏扩展状态（由扩展写入 App Group，主 App 轮询读取）
    @Published var extensionStatusText = "未检测到录屏扩展活动（请先开始一次录屏）"
    private var statusTimer: Timer?

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

    /// 显示用版本号，含构建号（用于确认是否装上了最新构建）
    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (build \(b))"
    }

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

    // MARK: - 录屏扩展状态轮询

    func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 先检测 App Group 是否可用：免费证书侧载下通常不可用，导致共享通道断开
            let agAvailable = SharedStorage.containerURL != nil
            guard let dict = SharedStorage.loadExtensionStatus(),
                  let lastActive = dict["lastActive"] as? String else {
                DispatchQueue.main.async {
                    if !agAvailable {
                        self.extensionStatusText = "⚠️ App Group 共享不可用\n（免费证书侧载常见，扩展与主App无法通信）\n→ 需付费开发者证书，或回复「走方案B」让扩展自带题库"
                    } else {
                        self.extensionStatusText = "未检测到录屏扩展活动\n（请先在控制中心开始一次录屏）"
                    }
                }
                return
            }
            let lastText = (dict["lastText"] as? String) ?? "（无）"
            let lastMatch = (dict["lastMatch"] as? String) ?? "（未匹配）"
            let started = (dict["startedAt"] as? String) ?? lastActive
            DispatchQueue.main.async {
                self.extensionStatusText = "启动于：\(started)\n最后活跃：\(lastActive)\n识别文本：\(lastText)\n最近匹配：\(lastMatch)"
            }
        }
    }

    func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
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
