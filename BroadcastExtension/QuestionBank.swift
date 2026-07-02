import Foundation
import CoreGraphics

// MARK: - 题目模型（Extension 自包含，不依赖主 App）

struct Question: Codable, Hashable {
    let text: String
    let type: String
    let answer: String
}

struct MatchResult {
    let question: Question
    let similarity: Double
}

// MARK: - 题库（Extension 版，只读，从 App Group 加载）

class QuestionBank {

    // MARK: - 拼音工具（内嵌，不依赖主 App）

    private static let pinyinMap: [String: String] = [
        "题": "ti", "目": "mu", "答": "da", "案": "an",
        "单": "dan", "选": "xuan", "多": "duo", "判": "pan", "断": "duan",
        "对": "dui", "错": "cuo", "是": "shi", "否": "fou",
        "不": "bu", "正": "zheng", "确": "que", "错误": "cuowu",
    ]

    private static func toPinyin(_ text: String) -> String {
        let cfStr = text as CFString
        var pinyin = [UniChar]()
        let range = CFRangeMake(0, CFStringGetLength(cfStr))
        let maxCount = CFStringGetMaximumSizeForEncoding(CFStringGetLength(cfStr), CFStringBuiltInEncodings.UTF8.rawValue)
        pinyin.reserveCapacity(maxCount)
        // 简化版：直接用 NSLinguisticTagger 获取拼音
        let tagger = NSLinguisticTagger(tagSchemes: [.script], options: 0)
        tagger.string = text
        // 降级：用 unicode 标量值作为拼音替代
        return text.unicodeScalars.map { String($0.value, radix: 36) }.joined()
    }

    private static func phoneticSim(_ a: String, _ b: String) -> Double {
        let pa = toPinyin(a).prefix(20)
        let pb = toPinyin(b).prefix(20)
        let maxLen = max(pa.count, pb.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshtein(String(pa), String(pb))
        return 1.0 - Double(min(distance, maxLen)) / Double(maxLen)
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let (m, n) = (a.count, b.count)
        guard m > 0 else { return n }
        guard n > 0 else { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
            }
        }
        return dp[m][n]
    }

    // MARK: - 倒排索引

    private(set) var questions: [Question] = []
    private var pinyinIndex: [String: [Int]] = [:]  // pinyin bigram -> question indices

    // MARK: - 加载（从 App Group 共享容器）

    func load() {
        let fm = FileManager.default
        let appGroupID = "group.com.leelemo.flashanswer"
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // fallback to documents
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            load(from: docs.appendingPathComponent("question_bank.json"))
            return
        }
        let url = container.appendingPathComponent("question_bank.json")
        load(from: url)
    }

    private func load(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Question].self, from: data)
            self.questions = decoded
            buildIndex()
        } catch {
            print("[FlashAnswer Ext] 加载题库失败: \(error)")
        }
    }

    // MARK: - 匹配

    func match(recognizedText: String, typeFilter: String? = nil) -> [MatchResult] {
        guard !questions.isEmpty else { return [] }

        let cleaned = recognizedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        // 先按题型过滤
        let candidates: [Question]
        if let filter = typeFilter, !filter.isEmpty {
            candidates = questions.filter { $0.type == filter }
        } else {
            candidates = questions
        }

        guard !candidates.isEmpty else { return [] }

        // 用拼音索引快速筛选候选
        let topCandidates = candidatesByIndex(cleaned, topN: 20)

        // 精细匹配
        var results: [MatchResult] = []
        for q in topCandidates {
            let sim = max(
                fuzzyMatch(text1: cleaned, text2: q.text),
                Self.phoneticSim(cleaned, q.text)
            )
            if sim >= 0.6 {
                results.append(MatchResult(question: q, similarity: sim))
            }
        }

        return results.sorted { $0.similarity > $1.similarity }
    }

    // MARK: - 模糊匹配

    private func fuzzyMatch(text1: String, text2: String) -> Double {
        let maxLen = max(text1.count, text2.count)
        guard maxLen > 0 else { return 1.0 }
        let dist = Self.levenshtein(text1, text2)
        return 1.0 - Double(min(dist, maxLen)) / Double(maxLen)
    }

    // MARK: - 拼音索引构建

    private func buildIndex() {
        pinyinIndex.removeAll()
        for (idx, q) in questions.enumerated() {
            let py = Self.toPinyin(q.text)
            let bigrams = pyBigrams(py)
            for bg in bigrams {
                pinyinIndex[bg, default: []].append(idx)
            }
        }
    }

    private func pyBigrams(_ py: String) -> [String] {
        let chars = Array(py)
        guard chars.count >= 2 else { return chars.map { String($0) } }
        var result: [String] = []
        for i in 0..<chars.count-1 {
            result.append(String(chars[i]) + String(chars[i+1]))
        }
        return result
    }

    private func candidatesByIndex(_ text: String, topN: Int) -> [Question] {
        let py = Self.toPinyin(text)
        let bigrams = pyBigrams(py)
        var score: [Int: Int] = [:]
        for bg in bigrams {
            if let indices = pinyinIndex[bg] {
                for idx in indices {
                    score[idx, default: 0] += 1
                }
            }
        }
        let sorted = score.sorted { $0.value > $1.value }.prefix(topN)
        return sorted.map { questions[$0.key] }
    }
}
