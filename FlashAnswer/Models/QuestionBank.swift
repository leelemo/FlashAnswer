import Foundation
import Combine

class QuestionBank: ObservableObject {
    @Published private(set) var questions: [Question] = []

    // 倒排索引：拼音 token -> [question index]
    private var invertedIndex: [String: Set<Int>] = [:]

    private let saveURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("question_bank.json")
    }()

    init() {
        load()
    }

    // MARK: - Import

    func importQuestions(_ newQuestions: [Question]) {
        for q in newQuestions {
            if !questions.contains(where: { $0.normalizedText == q.normalizedText }) {
                let idx = questions.count
                questions.append(q)
                indexQuestion(q, at: idx)
            }
        }
        save()
    }

    // MARK: - Clear

    func clearAll() {
        questions = []
        invertedIndex = [:]
        try? FileManager.default.removeItem(at: saveURL)
    }

    // MARK: - Match

    struct MatchResult {
        let question: Question
        let editDistance: Int
    }

    /// 匹配流程：倒排索引粗筛 → 滑动窗口拼音编辑距离
    /// 返回所有编辑距离 ≤3 的命中，按距离升序排列
    func match(recognizedText: String) -> [MatchResult] {
        // 先去掉识别文本中的标点符号，再转拼音
        let cleanedText = Question.cleanText(recognizedText)
        let recognizedPinyin = PinyinConverter.convert(cleanedText)
            .components(separatedBy: .whitespaces).joined()

        guard !recognizedPinyin.isEmpty else { return [] }

        // 倒排索引粗筛候选集
        var candidateIndices = Set<Int>()
        let tokens = tokenizePinyin(recognizedPinyin)
        for token in tokens {
            if let hits = invertedIndex[token] { candidateIndices.formUnion(hits) }
        }
        if candidateIndices.isEmpty {
            candidateIndices = Set(questions.indices)
        }

        // 滑动窗口拼音编辑距离
        var results: [MatchResult] = []
        let recognizedSyllables = syllables(from: recognizedPinyin)

        for idx in candidateIndices {
            let q = questions[idx]
            let qPinyin = q.pinyin.components(separatedBy: .whitespaces).joined()
            let qSyllables = syllables(from: qPinyin)

            let minDist = slidingWindowMinDistance(
                pattern: recognizedSyllables,
                text: qSyllables
            )

            if minDist <= 3 {
                results.append(MatchResult(question: q, editDistance: minDist))
            }
        }

        results.sort { $0.editDistance < $1.editDistance }
        return results
    }

    // MARK: - 滑动窗口编辑距离

    /// 在 text 上滑动窗口，找与 pattern 最小编辑距离
    private func slidingWindowMinDistance(pattern: [String], text: [String]) -> Int {
        if pattern.isEmpty { return text.count }
        if text.isEmpty { return pattern.count }

        // 如果 pattern 比 text 长，直接算整体编辑距离
        if pattern.count > text.count {
            return editDistance(pattern, text)
        }

        var minDist = Int.max
        let windowSize = pattern.count

        for start in 0...(text.count - windowSize) {
            let window = Array(text[start..<(start + windowSize)])
            let dist = editDistance(pattern, window)
            if dist < minDist {
                minDist = dist
                if minDist == 0 { break } // 完美匹配，提前退出
            }
        }

        return minDist
    }

    // MARK: - 拼音音节切分

    /// 将连续拼音字符串切成音节数组
    /// 如 "zaiyuangongzuo" → ["zai", "yuan", "gong", "zuo"]
    private func syllables(from pinyin: String) -> [String] {
        // 简单策略：按空格切分（CFStringTransform 会加空格）
        let parts = pinyin.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count > 1 { return parts }

        // 如果没有空格，用声母韵母规则切分
        return splitPinyinSyllables(pinyin)
    }

    /// 按拼音声母切分连续拼音
    private func splitPinyinSyllables(_ s: String) -> [String] {
        let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t",
                        "n", "l", "g", "k", "h", "j", "q", "x", "r",
                        "z", "c", "s", "y", "w", "a", "o", "e"]
        var result: [String] = []
        var current = ""
        let chars = Array(s)

        var i = 0
        while i < chars.count {
            if current.isEmpty {
                current.append(chars[i])
                i += 1
            } else {
                // 尝试匹配 2 字母声母
                if i + 1 <= chars.count {
                    let twoChar = String(chars[i]) + (i + 1 < chars.count ? String(chars[i + 1]) : "")
                    let oneChar = String(chars[i])

                    if initials.contains(twoChar) && !current.isEmpty {
                        result.append(current)
                        current = twoChar
                        i += 2
                    } else if initials.contains(oneChar) {
                        result.append(current)
                        current = oneChar
                        i += 1
                    } else {
                        current.append(chars[i])
                        i += 1
                    }
                } else {
                    current.append(chars[i])
                    i += 1
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - 编辑距离（音节数组级别）

    private func editDistance(_ a: [String], _ b: [String]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1])
                }
            }
        }
        return dp[m][n]
    }

    // MARK: - 倒排索引

    private func indexQuestion(_ q: Question, at idx: Int) {
        for token in tokenizePinyin(q.pinyin.components(separatedBy: .whitespaces).joined()) {
            invertedIndex[token, default: []].insert(idx)
        }
    }

    private func tokenizePinyin(_ s: String) -> [String] {
        let syllableArray = syllables(from: s)
        // 用 2-gram 做倒排索引 token
        var tokens: [String] = []
        for i in 0..<max(0, syllableArray.count - 1) {
            tokens.append(syllableArray[i] + syllableArray[i+1])
        }
        if syllableArray.count == 1 { tokens.append(syllableArray[0]) }
        return tokens
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(questions) {
            try? data.write(to: saveURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let saved = try? JSONDecoder().decode([Question].self, from: data) else { return }
        questions = saved
        for (idx, q) in questions.enumerated() { indexQuestion(q, at: idx) }
    }
}
