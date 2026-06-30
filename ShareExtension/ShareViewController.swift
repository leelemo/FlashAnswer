import UIKit
import UniformTypeIdentifiers
import Vision
import UserNotifications

/// Share Extension 入口：接收截图 → OCR → 匹配 → 通知
class ShareViewController: UIViewController {

    private let bank = QuestionBank()
    private var hasFired = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        bank.load()
        handleSharedItems()
    }

    // MARK: - UI

    private func setupUI() {
        let label = UILabel()
        label.text = "FlashAnswer 识别中…"
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])
    }

    // MARK: - Handle shared items

    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close(after: 1.5)
            return
        }

        var imageFound = false

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageFound = true
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) {
                        [weak self] item, _ in
                        guard let self, !self.hasFired else { return }
                        let image: UIImage?
                        if let url = item as? URL {
                            image = UIImage(contentsOfFile: url.path)
                        } else {
                            image = item as? UIImage
                        }
                        if let image {
                            self.recognizeText(in: image)
                        } else {
                            self.close(after: 1.5)
                        }
                    }
                    break
                }
            }
            if imageFound { break }
        }

        if !imageFound {
            close(after: 1.5)
        }
    }

    // MARK: - Vision OCR

    private func recognizeText(in image: UIImage) {
        guard let cgImage = image.cgImage else { close(after: 1.5); return }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.count > 1 }
                .joined(separator: "\n")
            self.handleOCRResult(text: recognizedText)
        }

        // 中文识别，快速模式
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        request.recognitionLevel = .fast

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    // MARK: - Match & Notify

    private func handleOCRResult(text: String) {
        guard !hasFired else { return }
        hasFired = true

        if text.isEmpty || bank.questions.isEmpty {
            sendNoMatchNotification()
        } else {
            let results = bank.match(recognizedText: text)
            if results.isEmpty {
                sendNoMatchNotification()
            } else {
                sendMatchNotifications(results: results)
            }
        }

        // 延迟关闭，让用户看到通知
        close(after: 2.0)
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
                identifier: "FlashAnswer-OCR-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func sendNoMatchNotification() {
        let content = UNMutableNotificationContent()
        content.title = "FlashAnswer OCR"
        content.body = "未能匹配到题目，请确认题库已导入"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Close

    private func close(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
