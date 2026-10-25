import Foundation

/// A unit that lengths can be entered or shown in.
enum LengthUnit: String, CaseIterable, Identifiable {
    case millimeters = "mm"
    case centimeters = "cm"
    case meters = "m"
    case inches = "in"
    case feet = "ft"

    var id: String { rawValue }
    var symbol: String { rawValue }

    /// How many millimetres one of this unit is.
    var millimeters: Double {
        switch self {
        case .millimeters: return 1
        case .centimeters: return 10
        case .meters: return 1000
        case .inches: return 25.4
        case .feet: return 304.8
        }
    }

    /// Formats a length given in millimetres, in this unit, e.g. "72.11 mm".
    func format(millimeters value: Double, locale: Locale = .current) -> String {
        "\(Self.number(value / millimeters, locale: locale)) \(symbol)"
    }

    /// Formats a value to about four significant figures, which is as precise as clicking
    /// points on a photo gets.
    static func number(_ value: Double, locale: Locale = .current) -> String {
        let magnitude = abs(value)
        let decimals = magnitude >= 1000 ? 0 : magnitude >= 100 ? 1 : magnitude >= 10 ? 2 : magnitude >= 1 ? 3 : 4
        return value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never).locale(locale))
    }

    /// Parses a typed length such as "100", "12.5" or "12,5". Returns nil unless it's a positive number.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }
}
