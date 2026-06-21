import Foundation

struct Question: Codable, Identifiable {
    let id: UUID
    let type: String        // 题型：单选/多选/判断/填空等
    let text: String        // 题干
    let answer: String      // 答案
    var normalizedText: String
    var pinyin: String      // 题干预计算的拼音

    init(id: UUID = UUID(), type: String, text: String, answer: String) {
        self.id = id
        self.type = type
        self.text = text
        self.answer = answer
        let cleaned = Question.cleanText(text)
        self.normalizedText = cleaned.lowercased()
        self.pinyin = PinyinConverter.convert(cleaned)
    }

    /// 去掉所有标点符号（中英文），只保留汉字、字母、数字、空格
    static func cleanText(_ s: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        return s.unicodeScalars.filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ s: String) -> String {
        return cleanText(s).lowercased()
    }
}

// MARK: - 拼音转换

enum PinyinConverter {
    /// 将中文转为无声调拼音，如 "中国" → "zhong guo"
    static func convert(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        // 转拉丁字母（带声调）
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        // 去除声调符号
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }
}
