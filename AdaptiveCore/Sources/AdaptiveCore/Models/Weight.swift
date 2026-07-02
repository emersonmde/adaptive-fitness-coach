import Foundation

/// A training load, stored canonically in **pounds**.
///
/// This is a plain value type rather than Foundation's `Measurement<UnitMass>` on purpose:
/// `Measurement` carries an `NSUnit` class, which complicates the `Sendable` conformance every
/// model in this package relies on. Pounds is the unit the seed weights are authored in and the
/// unit the watch's ± adjust steps in; the UI converts to kilograms for locales that prefer it
/// (`displayString(locale:)`). It is a seed, not a log (N7).
public struct Weight: Codable, Sendable, Hashable, Comparable {
    /// Canonical magnitude in pounds.
    public var pounds: Double

    public init(pounds: Double) {
        self.pounds = pounds
    }

    /// Convenience constructor reading as `.lb(15)`.
    public static func lb(_ pounds: Double) -> Weight { Weight(pounds: pounds) }

    public var kilograms: Double { pounds * 0.45359237 }

    public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.pounds < rhs.pounds }

    /// Add/subtract a delta (in pounds), clamped at zero so a load can never go negative.
    public func adjusted(byPounds delta: Double) -> Weight {
        Weight(pounds: max(0, pounds + delta))
    }

    /// A localized display string, e.g. `"15 lb"` or `"7 kg"`, using the locale's preferred
    /// mass unit. Rounds kilograms to the nearest whole number (dumbbell granularity).
    public func displayString(locale: Locale = .current) -> String {
        let usesMetric = locale.measurementSystem == .metric
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = usesMetric ? 0 : 1
        let measurement = usesMetric
            ? Measurement(value: (kilograms).rounded(), unit: UnitMass.kilograms)
            : Measurement(value: pounds, unit: UnitMass.pounds)
        return formatter.string(from: measurement)
    }
}
