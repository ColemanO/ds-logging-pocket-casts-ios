import Foundation

/// Sub-type of a "talking" entry — the part that prefixes the description string.
enum TalkingSubType: String, CaseIterable, Identifiable {
    case talking = "Talking"
    case crosstalk = "Crosstalk"
    case reverseCrosstalk = "Reverse Crosstalk"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

/// Discriminated representation of a manual entry the user creates.
/// Encodes to `(apiType, description)` for submission; decodes back from
/// the same pair when reading entries from Dreaming Spanish.
enum ManualEntryKind: Equatable {
    case watching(source: String, title: String)
    case talking(subType: TalkingSubType, userDescription: String?)

    /// Maps to the Dreaming Spanish `type` field.
    var apiType: String {
        switch self {
        case .watching: return "watching"
        case .talking: return "talking"
        }
    }

    /// Builds the description string we send to Dreaming Spanish.
    /// Watching: "<source> | <title>"; if only one side has content, no pipe.
    /// Talking: "<SubType>" alone or "<SubType> | <user desc>" if present.
    var encodedDescription: String {
        switch self {
        case .watching(let source, let title):
            let s = source.trimmingCharacters(in: .whitespaces)
            let t = title.trimmingCharacters(in: .whitespaces)
            switch (s.isEmpty, t.isEmpty) {
            case (false, false): return "\(s) | \(t)"
            case (false, true):  return s
            case (true, false):  return t
            case (true, true):   return ""
            }
        case .talking(let subType, let userDescription):
            let trimmed = userDescription?.trimmingCharacters(in: .whitespaces) ?? ""
            return trimmed.isEmpty ? subType.rawValue : "\(subType.rawValue) | \(trimmed)"
        }
    }

    /// Parses a Dreaming Spanish entry back into its manual-entry shape.
    /// Returns nil for entries that don't match the manual format
    /// (podcast auto-logs, the `initial` lifetime entry, or legacy
    /// "Crosstalk Session" / "Output Session" strings).
    static func decode(apiType: String, description: String) -> ManualEntryKind? {
        let parts = description.components(separatedBy: " | ")
        let group = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let specific = parts.count > 1
            ? parts.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
            : ""

        switch apiType {
        case "watching":
            // Defensive: an entry with no source AND no title is meaningless.
            // Treat as undecodable so the UI falls back to the raw string.
            if group.isEmpty && specific.isEmpty { return nil }
            return .watching(source: group, title: specific)
        case "talking":
            guard let subType = TalkingSubType(rawValue: group) else {
                return nil // legacy talking entry; render the raw description as-is
            }
            return .talking(subType: subType, userDescription: specific.isEmpty ? nil : specific)
        default:
            return nil // listening (podcasts), initial, etc. — not manual entries
        }
    }
}
