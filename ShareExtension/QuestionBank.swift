import Foundation

// MARK: - 题库模型（Extension 自包含版）

// MARK: - 拼音转换

enum PinyinConverter {
    static func convert(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }
}

// MARK: - 题目模型

struct Question: Codable, Identifiable {
    let id: UUID
    let type: String
    let text: String
    let answer: String
    var normalizedText: String
    var pinyin: String

    init(id: UUID = UUID(), type: String, text: String, answer: String) {
        self.id = id
        self.type = type
        self.text = text
        self.answer = answer
        let cleaned = Question.cleanText(text)
        self.normalizedText = cleaned.lowercased()
        self.pinyin = PinyinConverter.convert(cleaned)
    }

    static func cleanText(_ s: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        return s.unicodeScalars.filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 题库（只读，仅匹配）

class QuestionBank {
    private(set) var questions: [Question] = []
    private var invertedIndex: [String: Set<Int>] = [:]

    struct MatchResult {
        let question: Question
        let editDistance: Int
    }

    /// 从 App Group 加载题库（只读）
    func load() {
        guard let url = SharedStorage.questionBankURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([Question].self, from: data) else { return }
        questions = saved
        for (idx, q) in questions.enumerated() { indexQuestion(q, at: idx) }
    }

    // MARK: - 匹配（复用主 App 完全相同逻辑）

    func match(recognizedText: String) -> [MatchResult] {
        let cleanedText = Question.cleanText(recognizedText)
        let recognizedPinyin = PinyinConverter.convert(cleanedText)
            .components(separatedBy: .whitespaces).joined()

        guard !recognizedPinyin.isEmpty else { return [] }

        var candidateIndices = Set<Int>()
        let tokens = tokenizePinyin(recognizedPinyin)
        for token in tokens {
            if let hits = invertedIndex[token] { candidateIndices.formUnion(hits) }
        }
        if candidateIndices.isEmpty {
            candidateIndices = Set(questions.indices)
        }

        var results: [MatchResult] = []
        let recognizedSyllables = syllables(from: recognizedPinyin)

        for idx in candidateIndices {
            let q = questions[idx]
            let qPinyin = q.pinyin.components(separatedBy: .whitespaces).joined()
            let qSyllables = syllables(from: qPinyin)

            let minDist = slidingWindowMinDistance(pattern: recognizedSyllables, text: qSyllables)
            if minDist <= 3 {
                results.append(MatchResult(question: q, editDistance: minDist))
            }
        }

        results.sort { $0.editDistance < $1.editDistance }
        return Array(results.prefix(5))
    }

    // MARK: - 私有方法（与主 App 完全一致）

    private func indexQuestion(_ q: Question, at idx: Int) {
        for token in tokenizePinyin(q.pinyin.components(separatedBy: .whitespaces).joined()) {
            invertedIndex[token, default: []].insert(idx)
        }
    }

    private func tokenizePinyin(_ s: String) -> [String] {
        let syllableArray = syllables(from: s)
        var tokens: [String] = []
        for i in 0..<max(0, syllableArray.count - 1) {
            tokens.append(syllableArray[i] + syllableArray[i + 1])
        }
        if syllableArray.count == 1 { tokens.append(syllableArray[0]) }
        return tokens
    }

    private func syllables(from pinyin: String) -> [String] {
        let parts = pinyin.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.count > 1 { return parts }
        return splitPinyinSyllables(pinyin)
    }

    private func splitPinyinSyllables(_ s: String) -> [String] {
        let initials = ["zh","ch","sh","b","p","m","f","d","t",
                        "n","l","g","k","h","j","q","x","r",
                        "z","c","s","y","w","a","o","e"]
        var result: [String] = []
        var current = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if current.isEmpty {
                current.append(chars[i])
                i += 1
            } else {
                if i + 1 < chars.count {
                    let two = String(chars[i]) + String(chars[i + 1])
                    let one = String(chars[i])
                    if initials.contains(two) && !current.isEmpty {
                        result.append(current); current = two; i += 2
                    } else if initials.contains(one) {
                        result.append(current); current = one; i += 1
                    } else { current.append(chars[i]); i += 1 }
                } else { current.append(chars[i]); i += 1 }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func slidingWindowMinDistance(pattern: [String], text: [String]) -> Int {
        if pattern.isEmpty { return text.count }
        if text.isEmpty { return pattern.count }
        if pattern.count > text.count { return editDistance(pattern, text) }
        var minDist = Int.max
        let windowSize = pattern.count
        for start in 0...(text.count - windowSize) {
            let dist = editDistance(pattern, Array(text[start..<(start + windowSize)]))
            if dist < minDist { minDist = dist; if minDist == 0 { break } }
        }
        return minDist
    }

    private func editDistance(_ a: [String], _ b: [String]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = (a[i-1] == b[j-1]) ? dp[i-1][j-1] : 1 + min(dp[i-1][j-1], dp[i-1][j], dp[i][j-1])
            }
        }
        return dp[m][n]
    }
}
