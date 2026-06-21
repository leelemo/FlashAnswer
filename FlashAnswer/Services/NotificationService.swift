import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func sendAnswer(question: String, answer: String, options: String) {
        let content = UNMutableNotificationContent()
        content.title = "已找到答案"
        content.body = options.isEmpty
            ? "答案：\(answer)"
            : "\(options)\n答案：\(answer)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func sendNoMatch(recognizedText: String) {
        let content = UNMutableNotificationContent()
        content.title = "未匹配到题目"
        content.body = "识别到：\(recognizedText)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
