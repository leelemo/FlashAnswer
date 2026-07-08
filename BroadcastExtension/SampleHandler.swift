import ReplayKit
import Vision
import UserNotifications
import CoreMedia
import Dispatch

/// Broadcast Upload Extension 入口：接收录屏帧 → OCR → 匹配 → 通知
class SampleHandler: RPBroadcastSampleHandler {

    private let bank = QuestionBank()
    private var lastOCRTime: TimeInterval = 0
    private let ocrInterval: TimeInterval = 2.0  // 每 2 秒 OCR 一次

    // 反馈相关
    private var feedbackTimer: DispatchSourceTimer?
    private let feedbackInterval: TimeInterval = 10.0  // 每 10 秒一次反馈
    private var lastFeedbackAt: TimeInterval = 0
    private var foundSinceLastFeedback = false
    private var hasSentMatch = false

    override init() {
        super.init()
        bank.load()
    }

    // MARK: - 接收视频帧

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // 只处理视频帧
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        guard now - lastOCRTime >= ocrInterval else { return }
        lastOCRTime = now

        // 将 CMSampleBuffer 转为 UIImage
        guard let image = imageFromSampleBuffer(sampleBuffer) else { return }

        // OCR 识别
        recognizeText(in: image)
    }

    // MARK: - CMSampleBuffer → UIImage

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Vision OCR

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.count > 1 }
                .joined(separator: "\n")

            if !recognizedText.isEmpty {
                self.handleOCRResult(text: recognizedText)
            }
        }

        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        request.recognitionLevel = .fast

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    // MARK: - 匹配 & 通知

    private func handleOCRResult(text: String) {
        guard !bank.questions.isEmpty else {
            // 题库为空：交给周期反馈去提示，这里不重复处理
            return
        }

        let results = bank.match(recognizedText: text)
        guard !results.isEmpty else { return }

        // 标记本周期已找到答案，避免 10 秒反馈误报“搜不到答案”
        foundSinceLastFeedback = true

        // 避免短时间内重复发送匹配通知
        guard !hasSentMatch else { return }
        hasSentMatch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.hasSentMatch = false
        }

        sendMatchNotifications(results: results)
    }

    private func sendMatchNotifications(results: [MatchResult]) {
        for (i, result) in results.enumerated() {
            let q = result.question
            let content = UNMutableNotificationContent()
            content.title = "【\(q.type)】答案：\(q.answer)"
            content.body = String(q.text.prefix(100))
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1 + Double(i) * 0.3, repeats: false)
            let request = UNNotificationRequest(
                identifier: "FlashAnswer-Screen-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - 周期反馈（每 10 秒）

    private func startFeedbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        timer.schedule(deadline: .now() + feedbackInterval, repeating: feedbackInterval)
        timer.setEventHandler { [weak self] in
            self?.sendPeriodicFeedback()
        }
        timer.resume()
        feedbackTimer = timer
        lastFeedbackAt = CACurrentMediaTime()
        foundSinceLastFeedback = false
    }

    private func sendPeriodicFeedback() {
        let now = CACurrentMediaTime()
        // 确保至少间隔一个 feedbackInterval 才触发（容差 1 秒）
        guard now - lastFeedbackAt >= feedbackInterval - 1.0 else { return }
        lastFeedbackAt = now

        if foundSinceLastFeedback {
            // 本周期已找到答案（匹配通知已发出），进入下一周期
            foundSinceLastFeedback = false
            return
        }

        // 10 秒内未找到答案 → 给出反馈
        let content = UNMutableNotificationContent()
        content.title = "🔍 搜不到答案"
        content.body = bank.questions.isEmpty
            ? "题库为空：请先在 FlashAnswer 主 App 中导入题库。"
            : "已识别屏幕，但题库中没有匹配项。请确认题目完整出现在画面内。"
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "FlashAnswer-Feedback-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Broadcast 生命周期

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // 录屏开始，请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        bank.load()

        // 启动即时反馈：让用户知道录屏识别已运行
        let start = UNMutableNotificationContent()
        start.title = "▶️ 录屏识别已启动"
        start.body = "每 10 秒反馈一次；识别到题目会立即推送答案。"
        start.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "FlashAnswer-Start-\(UUID().uuidString)",
            content: start,
            trigger: nil
        ))

        startFeedbackTimer()
    }

    override func broadcastFinished() {
        feedbackTimer?.cancel()
        feedbackTimer = nil
    }

    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable: Any]) {
        // 可选：处理应用信息
    }
}
