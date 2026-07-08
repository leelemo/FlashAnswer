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

    static var extensionStatusURL: URL? {
        containerURL?.appendingPathComponent("flashanswer_status.json")
    }

    /// 读取录屏扩展写入的状态（最后活跃时间 / 识别文本 / 最近匹配）
    static func loadExtensionStatus() -> [String: Any]? {
        guard let url = extensionStatusURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}
