import Foundation

/// Minimal CSV parser for the Refold Resource Doc export.
///
/// Handles:
///   - Quoted fields with embedded commas and newlines.
///   - Doubled quotes inside quoted fields ("" → ").
///   - LF and CRLF line endings.
///   - Trailing empty columns and missing trailing newline.
enum RecommendationsCSVParser {
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                // Swift treats CRLF as a single grapheme cluster; match the
                // combined form as well as bare CR / LF.
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    current.append(field)
                    field = ""
                } else if c == "\r\n" || c == "\n" || c == "\r" {
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                } else {
                    field.append(c)
                }
            }

            i = text.index(after: i)
        }

        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }

        return rows
    }
}
