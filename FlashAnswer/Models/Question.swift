import Foundation

struct Question: Codable, Identifiable {
    let id: UUID
    let text: String
    let options: String
    let answer: String
    var normalizedText: String

    init(id: UUID = UUID(), text: String, options: String, answer: String) {
        self.id = id
        self.text = text
        self.options = options
        self.answer = answer
        self.normalizedText = Question.normalize(text)
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}
