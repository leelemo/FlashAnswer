import Foundation
import CoreXLSX

class ExcelParserService {
    enum ParseError: Error {
        case cannotOpen
        case noWorksheet
        case emptyFile
    }

    /// Parse an xlsx file, expecting:
    /// Column A: question text
    /// Column B: options
    /// Column C: answer
    /// Row 1 is treated as header and skipped.
    static func parse(url: URL) throws -> [Question] {
        guard let file = XLSXFile(filepath: url.path) else { throw ParseError.cannotOpen }
        guard let worksheet = try file.parseWorksheetPaths().first,
              let ws = try? file.parseWorksheet(at: worksheet) else { throw ParseError.noWorksheet }

        let sharedStrings = try? file.parseSharedStrings()
        var questions: [Question] = []

        let rows = ws.data?.rows ?? []
        for row in rows.dropFirst() { // skip header
            let cells = row.cells
            func cellValue(_ col: String) -> String {
                guard let cell = cells.first(where: { $0.reference.column.value == col }) else { return "" }
                if let shared = sharedStrings, cell.type == .sharedString,
                   let idx = cell.value.flatMap(Int.init) {
                    return shared.items[idx].text ?? ""
                }
                return cell.value ?? ""
            }

            let text = cellValue("A").trimmingCharacters(in: .whitespacesAndNewlines)
            let options = cellValue("B").trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = cellValue("C").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, !answer.isEmpty else { continue }
            questions.append(Question(text: text, options: options, answer: answer))
        }

        if questions.isEmpty { throw ParseError.emptyFile }
        return questions
    }
}
