import Foundation

/// Human-readable progress strings shared by the app, notifications and the widget.
public enum ValueFormatting {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    private static let oneDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    /// Localized display form of a unit key (`steps` → `шагов`).
    public static func unit(_ key: String) -> String {
        guard !key.isEmpty else { return "" }
        return String(localized: String.LocalizationValue(key), bundle: .module)
    }

    /// `8 214` for steps, `7.5` for hours/km.
    public static func value(_ value: Double, unit: String) -> String {
        let formatter = (unit == "h" || unit == "km") ? oneDecimal : grouped
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    /// `8 214 / 8 000 steps`
    public static func progress(value: Double, target: Double, unit: String) -> String {
        let text = "\(Self.value(value, unit: unit)) / \(Self.value(target, unit: unit))"
        return unit.isEmpty ? text : "\(text) \(Self.unit(unit))"
    }

    /// `≥ 8 000 steps`
    public static func goal(target: Double, unit: String) -> String {
        unit.isEmpty ? "" : "≥ \(Self.value(target, unit: unit)) \(Self.unit(unit))"
    }
}
