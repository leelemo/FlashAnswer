import ReplayKit
import Vision
import UserNotifications
import CoreMedia

/// Broadcast Upload Extension 入口：接收录屏帧 → OCR → 匹配 → 通知
class SampleHandler: RPBroadcastSampleHandler {

    private let bank = QuestionBank()
    private var lastOCRTime: TimeInterval = 0
    private let ocrInterval: TimeInterval = 2.0  // 每 2 秒 OCR 一次
    private var hasSentNotification = false

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
        guard !bank.questions.isEmpty else { return }

        let results = bank.match(recognizedText: text)
        guard !results.isEmpty else { return }

        // 避免短时间内重复发送
        guard !hasSentNotification else { return }
        hasSentNotification = true

        // 延迟后重置，避免一直不发送
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.hasSentNotification = false
        }

        sendMatchNotifications(results: results)
    }

    private func sendMatchNotifications(results: [QuestionBank.MatchResult]) {
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

    // MARK: - Broadcast 生命周期

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // 录屏开始，请求通知权限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        bank.load()
    }

    override func broadcastFinished() {
        // 录屏结束
    }

    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable: Any]) {
        // 可选：处理应用信息
    }
}
