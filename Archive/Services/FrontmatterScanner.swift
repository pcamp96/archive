import Foundation
import Yams

struct ParsedNoteFile {
    var frontmatter: FrontmatterDocument
    var body: String
}

struct FrontmatterScanner {
    func parse(_ source: String) -> ParsedNoteFile {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard lines.first == "---" else {
            return ParsedNoteFile(frontmatter: FrontmatterDocument(), body: normalized)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return ParsedNoteFile(frontmatter: FrontmatterDocument(), body: normalized)
        }

        let frontmatterLines = Array(lines[1..<closingIndex])
        var bodyLines = Array(lines[(closingIndex + 1)...])
        if bodyLines.first == "" {
            bodyLines.removeFirst()
        }

        let segments = segments(from: frontmatterLines.joined(separator: "\n"))
        return ParsedNoteFile(frontmatter: FrontmatterDocument(segments: segments), body: bodyLines.joined(separator: "\n"))
    }

    private func segments(from rawFrontmatter: String) -> [FrontmatterSegment] {
        guard rawFrontmatter.isEmpty == false else { return [] }
        let lines = rawFrontmatter.components(separatedBy: "\n")

        var chunks: [[String]] = []
        var current: [String] = []

        for line in lines {
            if isTopLevelPropertyLine(line), current.isEmpty == false {
                chunks.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        if current.isEmpty == false {
            chunks.append(current)
        }

        return chunks.map { parseChunk($0.joined(separator: "\n")) }
    }

    private func parseChunk(_ chunk: String) -> FrontmatterSegment {
        let lines = chunk.components(separatedBy: "\n")
        guard let first = lines.first, let key = keyName(from: first) else {
            return .raw(chunk)
        }

        do {
            let object = try Yams.load(yaml: chunk)
            guard let dictionary = object as? [String: Any], dictionary.count == 1, let value = dictionary[key] else {
                return .entry(FrontmatterEntry(key: key, rawContent: chunk, parsedValue: nil, issue: "Unsupported YAML structure."))
            }
            return .entry(
                FrontmatterEntry(
                    key: key,
                    rawContent: chunk,
                    parsedValue: parsePropertyValue(value, raw: chunk),
                    issue: nil
                )
            )
        } catch {
            return .entry(FrontmatterEntry(key: key, rawContent: chunk, parsedValue: nil, issue: "Malformed YAML: \(error.localizedDescription)"))
        }
    }

    private func keyName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let candidate = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        guard candidate.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else { return nil }
        return candidate
    }

    private func isTopLevelPropertyLine(_ line: String) -> Bool {
        guard line.first?.isWhitespace != true else { return false }
        return keyName(from: line) != nil
    }

    private func parsePropertyValue(_ value: Any, raw: String) -> PropertyValue? {
        if let boolValue = value as? Bool {
            return .bool(boolValue)
        }

        if let stringValue = value as? String {
            if isDateOnly(stringValue) {
                return .date(stringValue)
            }
            if isLikelyURL(stringValue) {
                return .url(stringValue)
            }
            return .string(stringValue)
        }

        if let dateValue = value as? Date {
            return .date(Self.dateFormatter.string(from: dateValue))
        }

        if let list = value as? [String] {
            return .stringList(list)
        }

        if let list = value as? [Any] {
            let strings = list.compactMap { $0 as? String }
            guard strings.count == list.count else { return nil }
            return .stringList(strings)
        }

        return nil
    }

    private func isDateOnly(_ string: String) -> Bool {
        string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private func isLikelyURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme?.isEmpty == false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
