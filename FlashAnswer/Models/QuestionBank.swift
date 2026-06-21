import Foundation

class QuestionBank: ObservableObject {
    @Published private(set) var questions: [Question] = []

    // Inverted index: normalized token -> [question index]
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

    // MARK: - Match

    /// Returns best matching question and its score, or nil if below threshold.
    func match(recognizedText: String, threshold: Double = 0.35) -> (question: Question, score: Double)? {
        let normalized = Question.normalize(recognizedText)
        guard !normalized.isEmpty else { return nil }

        let tokens = tokenize(normalized)
        var candidateIndices = Set<Int>()
        for token in tokens {
            if let hits = invertedIndex[token] { candidateIndices.formUnion(hits) }
        }

        if candidateIndices.isEmpty {
            // fallback: scan all
            candidateIndices = Set(questions.indices)
        }

        var bestScore = 0.0
        var bestQuestion: Question?

        for idx in candidateIndices {
            let q = questions[idx]
            let score = computeScore(input: normalized, questionText: q.normalizedText)
            if score > bestScore {
                bestScore = score
                bestQuestion = q
            }
        }

        guard let q = bestQuestion, bestScore >= threshold else { return nil }
        return (q, bestScore)
    }

    // MARK: - Private helpers

    private func indexQuestion(_ q: Question, at idx: Int) {
        for token in tokenize(q.normalizedText) {
            invertedIndex[token, default: []].insert(idx)
        }
    }

    private func tokenize(_ s: String) -> [String] {
        // Split by space, then add 2-char CJK bigrams
        var tokens: [String] = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let chars = Array(s)
        for i in 0..<max(0, chars.count - 1) {
            let bigram = String(chars[i...i+1])
            tokens.append(bigram)
        }
        return tokens
    }

    private func computeScore(input: String, questionText: String) -> Double {
        // Containment score
        let containment: Double = questionText.contains(input) || input.contains(questionText) ? 0.6 : 0.0

        // Edit distance score (normalized)
        let maxLen = max(input.count, questionText.count)
        guard maxLen > 0 else { return 0 }
        let dist = editDistance(input, questionText)
        let editScore = 1.0 - Double(dist) / Double(maxLen)

        // Token overlap score
        let inputTokens = Set(tokenize(input))
        let qTokens = Set(tokenize(questionText))
        let intersection = inputTokens.intersection(qTokens)
        let union = inputTokens.union(qTokens)
        let jaccardScore = union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)

        return containment * 0.4 + editScore * 0.3 + jaccardScore * 0.3
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...max(1, a.count) {
            var prev = dp[0]
            dp[0] = i
            for j in 1...max(1, b.count) {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1] ? prev : 1 + min(prev, min(dp[j], dp[j-1]))
                prev = temp
            }
        }
        return dp[b.count]
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

    func clearAll() {
        questions = []
        invertedIndex = [:]
        try? FileManager.default.removeItem(at: saveURL)
    }
}
