import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// 题型切换通知
    func sendTypeSwitched(type: String) {
        let content = UNMutableNotificationContent()
        content.title = "题型已切换"
        content.body = "当前题型：\(type)"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// 推送匹配到的题目答案，每道题一条通知
    func sendMatchedAnswers(results: [QuestionBank.MatchResult]) {
        for (i, result) in results.enumerated() {
            let q = result.question
            let content = UNMutableNotificationContent()
            content.title = "【\(q.type)】答案：\(q.answer)"
            content.body = q.text
            content.sound = .default
            content.userInfo = ["index": i, "total": results.count]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1 + Double(i) * 0.1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "FlashAnswer-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
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
