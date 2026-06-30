import Foundation

/// 管理 App Group 共享容器路径，主 App 和 Extension 共用
enum SharedStorage {
    /// 替换成你在开发者网站上注册的 App Group ID
    static let appGroupIdentifier = "group.com.leelemo.flashanswer"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    static var questionBankURL: URL? {
        containerURL?.appendingPathComponent("question_bank.json")
    }
}
