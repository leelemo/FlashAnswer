import Foundation
import CoreXLSX

class ExcelParserService {
    enum ParseError: Error {
        case cannotOpen
        case noWorksheet
        case emptyFile
    }

    /// 解析 xlsx 文件
    /// A列：题型（单选/多选/判断/填空等）
    /// B列：题干
    /// C列：答案
    /// 第一行为表头，自动跳过
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

            let type = cellValue("A").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = cellValue("B").trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = cellValue("C").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, !answer.isEmpty else { continue }
            questions.append(Question(type: type, text: text, answer: answer))
        }

        if questions.isEmpty { throw ParseError.emptyFile }
        return questions
    }
}
